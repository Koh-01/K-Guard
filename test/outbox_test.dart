import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nfc_guard/db.dart';
import 'package:nfc_guard/outbox_service.dart';
import 'package:nfc_guard/settings.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Fake Telegram server. [behaviour] decides the reply per chat id.
class FakeTelegram {
  final received = <String>[]; // "chatId:method"
  String Function(String chatId) behaviour = (_) => 'ok';

  http.Client client() => MockClient((req) async {
        final method = req.url.pathSegments.last;
        final body = req.headers['content-type']!.startsWith('multipart')
            ? utf8.decode(req.bodyBytes)
            : req.body;
        final chatId =
            RegExp(r'chat_id(?:=|"\r\n\r\n)(\d+)').firstMatch(body)!.group(1)!;
        switch (behaviour(chatId)) {
          case 'offline':
            throw const SocketException('offline');
          case 'blocked':
            return http.Response(
                jsonEncode({
                  'ok': false,
                  'error_code': 403,
                  'description': 'Forbidden: bot was blocked by the user'
                }),
                403);
          case 'slow_down':
            behaviour = (_) => 'ok'; // next attempt succeeds
            return http.Response(
                jsonEncode({
                  'ok': false,
                  'error_code': 429,
                  'description': 'Too Many Requests',
                  'parameters': {'retry_after': 1}
                }),
                429);
        }
        received.add('$chatId:$method');
        final result = method == 'sendPhoto'
            ? {
                'photo': [
                  {'file_id': 'F1'}
                ]
              }
            : {'message_id': 1};
        return http.Response(jsonEncode({'ok': true, 'result': result}), 200);
      });

  Future<void> run(Future<void> Function() f) => http.runWithClient(f, client);
}

Future<void> settle() async {
  // enqueue() starts delivery in the background; let it finish.
  for (var i = 0; i < 50; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  // Each test file gets its own database: test files run in parallel.
  setUpAll(() async => databaseFactory.setDatabasesPath(
      (await Directory.systemTemp.createTemp('kguard_db')).path));

  late FakeTelegram tg;

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'flutter.bot_token': 'TOKEN',
      'flutter.owners': jsonEncode([
        {'chat_id': '111', 'name': 'A'},
        {'chat_id': '222', 'name': 'B'},
      ]),
    });
    await AppSettings.init();
    await AppDb.instance.deleteAllLogs(); // also clears the outbox
    tg = FakeTelegram();
  });

  test('delivered to every owner, then removed from the queue', () async {
    await tg.run(() async {
      await OutboxService.enqueueText('hello');
      await settle();
    });
    expect(tg.received, ['111:sendMessage', '222:sendMessage']);
    expect(await OutboxService.pendingCount(), 0);
  });

  test('offline: kept in the queue and delivered later', () async {
    tg.behaviour = (_) => 'offline';
    await tg.run(() async {
      await OutboxService.enqueueText('hello');
      await settle();
    });
    expect(await OutboxService.pendingCount(), 1);
    expect(tg.received, isEmpty);

    tg.behaviour = (_) => 'ok';
    await tg.run(OutboxService.process);
    expect(tg.received, ['111:sendMessage', '222:sendMessage']);
    expect(await OutboxService.pendingCount(), 0);
  });

  test('partial failure: owner who already got it is not sent it again',
      () async {
    tg.behaviour = (chat) => chat == '222' ? 'offline' : 'ok';
    await tg.run(() async {
      await OutboxService.enqueueText('hello');
      await settle();
    });
    expect(tg.received, ['111:sendMessage']);
    expect(await OutboxService.pendingCount(), 1);

    tg.behaviour = (_) => 'ok';
    await tg.run(OutboxService.process);
    expect(
        tg.received, ['111:sendMessage', '222:sendMessage']); // 111 only once
    expect(await OutboxService.pendingCount(), 0);
  });

  test('owner who blocked the bot is skipped; the queue does not get stuck',
      () async {
    tg.behaviour = (chat) => chat == '111' ? 'blocked' : 'ok';
    await tg.run(() async {
      await OutboxService.enqueueText('one');
      await OutboxService.enqueueText('two');
      await settle();
    });
    expect(tg.received, ['222:sendMessage', '222:sendMessage']);
    expect(await OutboxService.pendingCount(), 0);
  });

  test('rate limited (429): waits and retries instead of failing', () async {
    tg.behaviour = (_) => 'slow_down';
    await tg.run(() async {
      await OutboxService.enqueueText('hello');
      await Future<void>.delayed(const Duration(milliseconds: 1500));
      await settle();
    });
    expect(tg.received, ['111:sendMessage', '222:sendMessage']);
    expect(await OutboxService.pendingCount(), 0);
  });

  test('photo: sent with sendPhoto; dropped if the file was deleted', () async {
    final f = File('${Directory.systemTemp.path}/outbox_test.jpg')
      ..writeAsBytesSync([1, 2, 3]);
    await tg.run(() async {
      await OutboxService.enqueuePhoto(f.path, caption: 'proof');
      await settle();
    });
    expect(tg.received, ['111:sendPhoto', '222:sendPhoto']);

    tg.behaviour = (_) => 'offline';
    await tg.run(() async {
      await OutboxService.enqueuePhoto(f.path);
      await settle();
    });
    expect(await OutboxService.pendingCount(), 1);
    f.deleteSync();
    await tg.run(OutboxService.process);
    expect(await OutboxService.pendingCount(), 0);
  });
}
