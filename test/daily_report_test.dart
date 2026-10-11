import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nfc_guard/daily_report_service.dart';
import 'package:nfc_guard/db.dart';
import 'package:nfc_guard/models.dart';
import 'package:nfc_guard/settings.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  setUpAll(() async => databaseFactory.setDatabasesPath(
      (await Directory.systemTemp.createTemp('kguard_db')).path));

  final received = <String>[]; // chat ids that got a message
  http.Client fakeTelegram() => MockClient((req) async {
        received.add(RegExp(r'chat_id=(\d+)').firstMatch(req.body)!.group(1)!);
        return http.Response(jsonEncode({'ok': true, 'result': {}}), 200);
      });
  Future<void> settle() async {
    for (var i = 0; i < 50; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
  }

  setUp(() async {
    received.clear();
    SharedPreferences.setMockInitialValues({
      'flutter.bot_token': 'TOKEN',
      'flutter.site_name': 'Palm Court',
      'flutter.owners': jsonEncode([
        {'chat_id': '111', 'name': 'Tan', 'daily_report': true},
        {'chat_id': '222', 'name': 'Lee', 'daily_report': false},
      ]),
    });
    await AppSettings.init();
    await AppDb.instance.deleteAllLogs();
  });

  test('report time and the 24-hour window', () {
    AppSettings.dailyReportMinute = 8 * 60;
    expect(DailyReportService.lastDue(DateTime(2026, 9, 30, 7, 59)),
        DateTime(2026, 9, 29, 8));
    expect(DailyReportService.lastDue(DateTime(2026, 9, 30, 8, 0)),
        DateTime(2026, 9, 30, 8));
    expect(DailyReportService.lastDue(DateTime(2026, 9, 30, 23, 0)),
        DateTime(2026, 9, 30, 8));
  });

  test('sent only to owners with Daily report on, and only once per day',
      () async {
    await http.runWithClient(() async {
      await DailyReportService.maybeSend();
      await settle();
      await DailyReportService.maybeSend(); // already sent today: nothing more
      await settle();
    }, fakeTelegram);
    expect(received, ['111']);
  });

  test('switching it on does not send immediately; the next report time does',
      () async {
    AppSettings.owners = [
      for (final o in AppSettings.owners)
        o.chatId == '222' ? o.copyWith(dailyReport: true) : o
    ];
    DailyReportService.startFromNext(AppSettings.owners.last);
    await http.runWithClient(() async {
      await DailyReportService.maybeSend();
      await settle();
    }, fakeTelegram);
    expect(received, ['111']); // 222 waits for the next report time
  });

  test('report content', () {
    final from = DateTime(2026, 9, 29, 8), to = DateTime(2026, 9, 30, 8);
    final gate = Checkpoint(tagId: 'A', name: 'Gate'),
        pool = Checkpoint(tagId: 'B', name: 'Pool');
    final text = DailyReportService.build(
      from: from,
      to: to,
      checkpoints: [gate, pool],
      logs: [
        CheckinLog(
            tagId: 'A',
            checkpointName: 'Gate',
            guardName: 'KOH',
            time: from.add(const Duration(hours: 1)),
            known: true),
        CheckinLog(
            tagId: 'A',
            checkpointName: 'Gate',
            guardName: 'Ali',
            time: from.add(const Duration(hours: 3)),
            known: true,
            photoRequired: true),
      ],
      incidents: [
        Incident(
            time: from.add(const Duration(hours: 5)),
            guardName: 'Ali',
            category: 'light',
            description: '',
            mediaType: 'photo'),
      ],
      rejected: [
        RejectedCheckin(
            time: from.add(const Duration(hours: 6)),
            guardName: 'KOH',
            tagId: 'B',
            checkpointName: 'Pool',
            reason: 'far'),
      ],
    );
    expect(text, contains('Daily Patrol Report'));
    expect(text, contains('29 Sep 08:00 → 30 Sep 08:00'));
    expect(text, contains('✅ Check-ins: 2'));
    expect(text, contains('• Gate: 2'));
    expect(text, contains('⚠️ Not patrolled: Pool'));
    expect(text, contains('📷 Photo proofs: 0/1 (⚠️ 1 missing)'));
    expect(text, contains('🚫 GPS problems: 1'));
    expect(text, contains('🚨 Incidents: 1 (Street light broken 1)'));
  });

  test(
      'old app-wide "notify every check-in" setting carries over to each owner',
      () async {
    SharedPreferences.setMockInitialValues({
      'flutter.instant_notify': true,
      'flutter.owners': jsonEncode([
        {'chat_id': '111', 'name': 'Tan'},
      ]),
    });
    await AppSettings.init();
    expect(AppSettings.owners.single.notifyCheckins, isTrue);
    expect(AppSettings.owners.single.dailyReport, isFalse);
  });

  test('monthly report: on by default, can be switched off per owner',
      () async {
    SharedPreferences.setMockInitialValues({
      'flutter.owners': jsonEncode([
        {'chat_id': '111', 'name': 'Tan'}, // saved before the switch existed
        {'chat_id': '222', 'name': 'Lee', 'monthly_report': false},
      ]),
    });
    await AppSettings.init();
    expect(AppSettings.owners.map((o) => o.monthlyReport), [true, false]);
    // Round-trips through storage.
    AppSettings.owners = AppSettings.owners;
    expect(AppSettings.owners.map((o) => o.monthlyReport), [true, false]);
  });

  test('alert options default to on for owners saved before they existed',
      () async {
    SharedPreferences.setMockInitialValues({
      'flutter.owners': jsonEncode([
        {'chat_id': '111', 'name': 'Tan'},
        {
          'chat_id': '222',
          'name': 'Lee',
          'gps_alerts': false,
          'proof_photos': false
        },
      ]),
    });
    await AppSettings.init();
    final a = AppSettings.owners.first, b = AppSettings.owners.last;
    expect([a.gpsAlerts, a.incidentReports, a.proofPhotos], [true, true, true]);
    expect(
        [b.gpsAlerts, b.incidentReports, b.proofPhotos], [false, true, false]);
    AppSettings.owners = AppSettings.owners; // round trip
    expect(AppSettings.owners.last.proofPhotos, isFalse);
  });
}
