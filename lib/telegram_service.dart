import 'dart:convert';

import 'package:http/http.dart' as http;

import 'settings.dart';

class TelegramException implements Exception {
  final String message;

  /// Telegram's error_code (e.g. 400 bad request, 403 blocked by user, 429 too many requests).
  final int? errorCode;

  /// For 429: how many seconds Telegram asks us to wait.
  final int? retryAfter;

  TelegramException(this.message, {this.errorCode, this.retryAfter});

  /// Retrying won't help for this recipient (bot blocked, chat not found, bad request).
  bool get permanent => errorCode == 400 || errorCode == 403;

  @override
  String toString() => message;
}

class TelegramService {
  static const _timeout = Duration(seconds: 30);

  static Uri _uri(String token, String method) =>
      Uri.parse('https://api.telegram.org/bot$token/$method');

  static Map<String, dynamic> _check(http.Response res) {
    Map<String, dynamic> body;
    try {
      body = jsonDecode(res.body) as Map<String, dynamic>;
    } catch (_) {
      throw TelegramException(
          'Unexpected Telegram response (HTTP ${res.statusCode})');
    }
    if (body['ok'] != true) {
      throw TelegramException(
        'Telegram error: ${body['description'] ?? res.statusCode}',
        errorCode: body['error_code'] as int? ?? res.statusCode,
        retryAfter: (body['parameters'] as Map?)?['retry_after'] as int?,
      );
    }
    return body;
  }

  /// Runs a Telegram call; if Telegram says "too many requests", waits as asked and retries.
  static Future<T> _rateLimited<T>(Future<T> Function() call) async {
    for (var attempt = 0;; attempt++) {
      try {
        return await call();
      } on TelegramException catch (e) {
        final wait = e.retryAfter;
        if (e.errorCode != 429 || wait == null || attempt >= 3) rethrow;
        await Future<void>.delayed(Duration(seconds: wait.clamp(1, 60)));
      }
    }
  }

  static Future<void> sendMessageTo(String chatId, String text) =>
      _rateLimited(() async {
        final res = await http.post(
          _uri(AppSettings.botToken, 'sendMessage'),
          body: {'chat_id': chatId, 'text': text},
        ).timeout(_timeout);
        _check(res);
      });

  static Future<void> sendDocumentTo(
          String chatId, List<int> bytes, String filename, {String? caption}) =>
      _rateLimited(
          () => _sendDocumentBytes(chatId, bytes, filename, caption: caption));

  static Future<void> _sendDocumentBytes(
      String chatId, List<int> bytes, String filename,
      {String? caption}) async {
    final req = http.MultipartRequest(
        'POST', _uri(AppSettings.botToken, 'sendDocument'))
      ..fields['chat_id'] = chatId
      ..files.add(
          http.MultipartFile.fromBytes('document', bytes, filename: filename));
    if (caption != null) req.fields['caption'] = caption;
    final streamed = await req.send().timeout(const Duration(minutes: 5));
    _check(await http.Response.fromStream(streamed));
  }

  /// Telegram file IDs of files already uploaded (local path -> file_id), so the same
  /// photo / video / voice note is uploaded once and forwarded to other owners instantly.
  static final _fileIds = <String, String>{};

  static String? _fileIdFrom(Map<String, dynamic> result, String field) {
    final media = result[field] ??
        result['video'] ??
        result['animation'] ??
        result['document'];
    if (media is List && media.isNotEmpty) {
      return (media.last as Map)['file_id'] as String?;
    }
    if (media is Map) return media['file_id'] as String?;
    return null;
  }

  /// Sends a local file with a Bot API method such as sendPhoto / sendVideo / sendVoice.
  static Future<void> _sendFile(
          String method, String field, String chatId, String path,
          {String? caption}) =>
      _rateLimited(
          () => _sendFileOnce(method, field, chatId, path, caption: caption));

  static Future<void> _sendFileOnce(
      String method, String field, String chatId, String path,
      {String? caption}) async {
    final cached = _fileIds[path];
    if (cached != null) {
      try {
        final res = await http.post(_uri(AppSettings.botToken, method), body: {
          'chat_id': chatId,
          field: cached,
          if (caption != null) 'caption': caption,
        }).timeout(_timeout);
        _check(res);
        return;
      } on TelegramException catch (e) {
        if (e.errorCode == 429) rethrow; // wait and retry, don't re-upload
        _fileIds.remove(path); // file ID rejected: fall back to uploading
      } catch (_) {
        _fileIds.remove(path);
      }
    }
    final req =
        http.MultipartRequest('POST', _uri(AppSettings.botToken, method))
          ..fields['chat_id'] = chatId
          ..files.add(await http.MultipartFile.fromPath(field, path));
    if (caption != null) req.fields['caption'] = caption;
    final streamed = await req.send().timeout(const Duration(minutes: 5));
    final body = _check(await http.Response.fromStream(streamed));
    final id = _fileIdFrom(body['result'] as Map<String, dynamic>, field);
    if (id != null) _fileIds[path] = id;
  }

  static Future<void> sendPhotoTo(String chatId, String path,
          {String? caption}) =>
      _sendFile('sendPhoto', 'photo', chatId, path, caption: caption);

  static Future<void> sendVideoTo(String chatId, String path,
          {String? caption}) =>
      _sendFile('sendVideo', 'video', chatId, path, caption: caption);

  static Future<void> sendDocumentFileTo(String chatId, String path,
          {String? caption}) =>
      _sendFile('sendDocument', 'document', chatId, path, caption: caption);

  static Future<void> sendVoiceTo(String chatId, String path,
          {String? caption}) =>
      _sendFile('sendVoice', 'voice', chatId, path, caption: caption);

  /// Runs [send] for each owner (all owners by default).
  /// Returns the owners that succeeded; throws if any owner failed, listing who and why.
  static Future<List<Owner>> toOwners(Future<void> Function(Owner o) send,
      {List<Owner>? owners}) async {
    if (AppSettings.botToken.isEmpty || AppSettings.owners.isEmpty) {
      throw TelegramException('Telegram Bot Token or owners are not set');
    }
    final ok = <Owner>[];
    final failed = <String>[];
    for (final o in owners ?? AppSettings.owners) {
      try {
        await send(o);
        ok.add(o);
      } catch (e) {
        failed.add('• ${o.name}: $e');
      }
    }
    if (failed.isNotEmpty) {
      throw TelegramException(
          'Sent to ${ok.length} of ${ok.length + failed.length} owners. Failed:\n${failed.join('\n')}');
    }
    return ok;
  }

  /// Sends a text message to every owner.
  static Future<void> sendMessage(String text) =>
      toOwners((o) => sendMessageTo(o.chatId, text));

  /// 列出最近给 Bot 发过消息的聊天，方便获取业主的 Chat ID。
  /// 业主需要先在 Telegram 里打开 Bot 并按 /start。
  static Future<List<({String id, String title})>> recentChats(
      String token) async {
    final res = await http.get(_uri(token, 'getUpdates')).timeout(_timeout);
    final body = _check(res);
    final seen = <String, String>{};
    for (final u in body['result'] as List) {
      final msg = u['message'] ?? u['my_chat_member'] ?? u['channel_post'];
      final chat = msg?['chat'];
      if (chat == null) continue;
      final id = chat['id'].toString();
      final title = chat['title'] ??
          [chat['first_name'], chat['last_name']].whereType<String>().join(' ');
      seen[id] =
          (chat['username'] != null ? '$title (@${chat['username']})' : title)
              .toString();
    }
    return seen.entries.map((e) => (id: e.key, title: e.value)).toList();
  }
}
