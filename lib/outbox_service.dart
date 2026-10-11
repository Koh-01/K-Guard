import 'dart:convert';
import 'dart:io';

import 'db.dart';
import 'settings.dart';
import 'telegram_service.dart';

/// Reliable delivery for fire-and-forget Telegram messages (instant check-in notices and
/// proof photos): each message is saved first, then delivered to every owner, and retried
/// until it arrives. Owners who already received it are never sent it again.
class OutboxService {
  /// Give up on messages that still can't be delivered after this long.
  static const maxAge = Duration(days: 7);

  static bool _running = false;
  static bool _again = false;

  /// Queues [text] for [targets] (owner chat IDs), or for every owner if null.
  static Future<void> enqueueText(String text, {List<String>? targets}) =>
      _enqueue('text', text: text, targets: targets);

  static Future<void> enqueuePhoto(String path,
          {String? caption, List<String>? targets}) =>
      _enqueue('photo', path: path, text: caption, targets: targets);

  static Future<void> _enqueue(String kind,
      {String? text, String? path, List<String>? targets}) async {
    if (!AppSettings.telegramConfigured) return;
    await AppDb.instance.addOutbox({
      'created_at': DateTime.now().millisecondsSinceEpoch,
      'kind': kind,
      'text': text,
      'path': path,
      // Recipients are fixed when the message is created: owners added later don't get old notices.
      'targets':
          jsonEncode(targets ?? [for (final o in AppSettings.owners) o.chatId]),
      'sent_to': '[]',
    });
    process(); // try right away, in the background
  }

  /// Delivers pending messages, oldest first. Safe to call often; does nothing if already running.
  static Future<void> process() async {
    if (AppSettings.botToken.isEmpty) return;
    if (_running) {
      _again =
          true; // something was queued meanwhile: pick it up before stopping
      return;
    }
    _running = true;
    try {
      do {
        _again = false;
        for (final row in await AppDb.instance.outbox()) {
          // Probably offline — stop and try again later, keeping the order.
          if (!await _deliver(row)) return;
        }
      } while (_again);
    } finally {
      _running = false;
    }
  }

  /// Returns false if delivery should pause (network / temporary error).
  static Future<bool> _deliver(Map<String, Object?> row) async {
    final id = row['id'] as int;
    final age = DateTime.now().difference(
        DateTime.fromMillisecondsSinceEpoch(row['created_at'] as int));
    final path = row['path'] as String?;
    if (age > maxAge || (path != null && !File(path).existsSync())) {
      await AppDb.instance.deleteOutbox(id);
      return true;
    }

    final currentOwners = {for (final o in AppSettings.owners) o.chatId};
    final targets =
        List<String>.from(jsonDecode(row['targets'] as String) as List)
            .where(currentOwners.contains); // skip owners removed since
    final sentTo =
        List<String>.from(jsonDecode(row['sent_to'] as String) as List);

    for (final chatId in targets) {
      if (sentTo.contains(chatId)) continue;
      try {
        if (row['kind'] == 'photo') {
          await TelegramService.sendPhotoTo(chatId, path!,
              caption: row['text'] as String?);
        } else {
          await TelegramService.sendMessageTo(chatId, row['text'] as String);
        }
        sentTo.add(chatId);
      } on TelegramException catch (e) {
        if (e.permanent) {
          sentTo.add(
              chatId); // blocked / chat not found: retrying won't help this owner
          continue;
        }
        await _recordFailure(id, sentTo, row, e);
        return false;
      } catch (e) {
        await _recordFailure(id, sentTo, row, e);
        return false;
      }
    }
    await AppDb.instance.deleteOutbox(id);
    return true;
  }

  static Future<void> _recordFailure(
          int id, List<String> sentTo, Map<String, Object?> row, Object e) =>
      AppDb.instance.updateOutbox(id, {
        'sent_to': jsonEncode(sentTo),
        'attempts': (row['attempts'] as int) + 1,
        'last_error': '$e',
      });

  static Future<int> pendingCount() => AppDb.instance.outboxCount();
}
