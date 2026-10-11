import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nfc_guard/db.dart';
import 'package:nfc_guard/models.dart';
import 'package:nfc_guard/pdf_report.dart';
import 'package:nfc_guard/report_service.dart';
import 'package:nfc_guard/settings.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  // Each test file gets its own database: test files run in parallel.
  setUpAll(() async => databaseFactory.setDatabasesPath(
      (await Directory.systemTemp.createTemp('kguard_db')).path));

  final far = RejectedCheckin(
    time: DateTime(2026, 9, 12, 2, 30),
    guardName: 'KOH',
    tagId: '04:AA',
    checkpointName: 'Gate',
    reason: 'far',
    distanceM: 849.6,
    lat: 3.1467,
    lng: 101.6869,
  );
  final noGps = RejectedCheckin(
    time: DateTime(2026, 9, 13, 3, 0),
    guardName: 'Ali',
    tagId: '04:BB',
    checkpointName: 'Pool',
    reason: 'none',
  );

  setUp(() async {
    SharedPreferences.setMockInitialValues({'flutter.site_name': 'Palm Court'});
    await AppSettings.init();
    await AppDb.instance.deleteAllLogs(); // also clears rejected attempts
  });

  test('stored and read back per month', () async {
    await AppDb.instance.addRejected(far);
    await AppDb.instance.addRejected(noGps);
    await AppDb.instance.addRejected(RejectedCheckin(
        time: DateTime(2026, 10, 1, 1),
        guardName: 'X',
        tagId: 'T',
        checkpointName: 'Gate',
        reason: 'mock'));
    final sept = await AppDb.instance.rejectedForMonth(2026, 9);
    expect(sept.map((r) => r.checkpointName), ['Pool', 'Gate']); // newest first
    expect(sept.last.distanceM, closeTo(849.6, 0.01));

    await AppDb.instance.deleteRejectedBefore(DateTime(2026, 10));
    expect(await AppDb.instance.rejectedForMonth(2026, 9), isEmpty);
    expect(await AppDb.instance.rejectedForMonth(2026, 10), hasLength(1));
  });

  test('summary message mentions rejected attempts', () async {
    final text = await ReportService.buildSummary(2026, 9, [],
        sentBy: 'test', rejected: [noGps, far]);
    expect(text, contains('🚫 Rejected check-ins (GPS): 2'));
    expect(text, contains('Gate (KOH) — Too far (850 m)'));
    expect(text, contains('Pool (Ali) — No GPS signal'));
  });

  test('PDF builds with a rejected check-ins section', () async {
    final bytes = await buildPdfReport(PdfReportInput(
      siteName: 'Palm Court',
      year: 2026,
      month: 9,
      sentBy: 'test',
      checkpointNames: ['Gate', 'Pool'],
      logs: [],
      incidents: [],
      rejected: [noGps, far],
    ));
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
  });
}
