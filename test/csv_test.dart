import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nfc_guard/models.dart';
import 'package:nfc_guard/report_service.dart';

List<String> csvLines(List<int> bytes) {
  expect(bytes.take(3), [0xEF, 0xBB, 0xBF]); // UTF-8 BOM for Excel
  return utf8.decode(bytes.sublist(3)).trim().split('\n');
}

void main() {
  final d = DateTime(2026, 9, 1);

  final checkins = [
    // newest first, as the database returns them
    CheckinLog(
        tagId: 'C',
        checkpointName: 'Lobby',
        guardName: 'Ali',
        time: d.add(const Duration(hours: 23)),
        known: true,
        photoRequired: true), // photo missing
    CheckinLog(
        tagId: 'A',
        checkpointName: 'Gate',
        guardName: 'KOH',
        time: d.add(const Duration(hours: 2)),
        known: true,
        photoRequired: true,
        photoPath: '/p.jpg',
        lat: 3.139,
        lng: 101.6869,
        distanceM: 12.4,
        gpsStatus: 'ok'),
    CheckinLog(
        tagId: 'X',
        checkpointName: 'Unregistered tag',
        guardName: 'KOH',
        time: d.add(const Duration(hours: 1)),
        known: false),
  ];
  final rejected = [
    RejectedCheckin(
        time: d.add(const Duration(hours: 3)),
        guardName: 'KOH',
        tagId: 'A',
        checkpointName: 'Gate',
        reason: 'far',
        distanceM: 849.6,
        lat: 3.1467,
        lng: 101.6869),
  ];
  final incidents = [
    Incident(
        time: d.add(const Duration(hours: 22)),
        guardName: 'Ali',
        category: 'fence',
        location: 'Block C',
        description: 'Panel bent, "1 m" gap',
        mediaType: 'photo',
        photoPaths: ['/a.jpg', '/b.jpg'],
        voicePath: '/v.m4a'),
  ];

  test('one file, one header, all record types in time order', () {
    final lines = csvLines(ReportService.buildCsv(checkins,
        incidents: incidents, rejected: rejected));
    expect(lines.first, ReportService.csvHeader);
    expect(lines, hasLength(6));
    expect(lines.skip(1).map((l) => l.split(',').first).toList(),
        ['Check-in', 'Check-in', 'Rejected (GPS)', 'Incident', 'Check-in']);
    // Every row has the same number of columns as the header (quoted commas aside).
    final cols = ReportService.csvHeader.split(',').length;
    for (final l in lines.skip(1)) {
      final unquoted = l.replaceAll(RegExp(r'"(?:[^"]|"")*"'), 'Q');
      expect(unquoted.split(','), hasLength(cols), reason: l);
    }
  });

  test('row contents', () {
    final lines = csvLines(ReportService.buildCsv(checkins,
        incidents: incidents, rejected: rejected));
    expect(lines[1],
        'Check-in,2026-09-01,01:00:00,"Unregistered tag","KOH",Unregistered tag,,,,,,X');
    expect(lines[2],
        'Check-in,2026-09-01,02:00:00,"Gate","KOH",OK,Taken,OK,12,"https://maps.google.com/?q=3.139000,101.686900",,A');
    expect(
        lines[3],
        'Rejected (GPS),2026-09-01,03:00:00,"Gate","KOH",Too far,,TOO FAR,850,"https://maps.google.com/?q=3.146700,101.686900",'
        'Check-in refused: phone was not at the checkpoint,A');
    expect(
        lines[4],
        'Incident,2026-09-01,22:00:00,"Block C","Ali","Broken fence",,,,,'
        '"Panel bent, ""1 m"" gap | Evidence: 2 photo(s) + voice note",');
    expect(lines[5],
        'Check-in,2026-09-01,23:00:00,"Lobby","Ali",OK,MISSING,,,,,C');
  });

  test('a month with only check-ins still works', () {
    final lines = csvLines(ReportService.buildCsv(checkins));
    expect(lines, hasLength(4));
  });
}
