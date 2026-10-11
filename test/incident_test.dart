import 'package:flutter_test/flutter_test.dart';
import 'package:nfc_guard/incident_service.dart';
import 'package:nfc_guard/models.dart';
import 'package:nfc_guard/settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({'site_name': 'Palm Court'});
    await AppSettings.init();
  });

  final incident = Incident(
    id: 7,
    time: DateTime(2026, 9, 25, 23, 40),
    guardName: 'Ali',
    category: 'fence',
    location: 'Car Park B2',
    description: 'Fence panel bent, gap of 1m',
    mediaType: 'photo',
    photoPaths: ['/a/1.jpg', '/a/2.jpg'],
    voicePath: '/a/v.m4a',
    sentTo: ['111'],
  );

  test('model round-trips through the DB map', () {
    final back = Incident.fromMap(incident.toMap());
    expect(back.category, 'fence');
    expect(back.photoPaths, ['/a/1.jpg', '/a/2.jpg']);
    expect(back.voicePath, '/a/v.m4a');
    expect(back.sentTo, ['111']);
    expect(back.allMediaPaths, ['/a/1.jpg', '/a/2.jpg', '/a/v.m4a']);
  });

  test('telegram message contains all details', () {
    final m = IncidentService.message(incident);
    expect(m, contains('INCIDENT REPORT — Palm Court'));
    expect(m, contains('🧱 Broken fence'));
    expect(m, contains('📍 Car Park B2'));
    expect(m, contains('👮 Ali'));
    expect(m, contains('2026-09-25 23:40'));
    expect(m, contains('Fence panel bent'));
  });

  test('fullySent only when every owner received it', () {
    AppSettings.owners = [const Owner('111', 'A'), const Owner('222', 'B')];
    expect(IncidentService.fullySent(incident), isFalse);
    AppSettings.owners = [const Owner('111', 'A')];
    expect(IncidentService.fullySent(incident), isTrue);
  });

  test('incident reports go only to owners who have them switched on', () {
    AppSettings.owners = [
      const Owner('111', 'A'),
      const Owner('222', 'B', incidentReports: false),
    ];
    expect(IncidentService.recipients().map((o) => o.chatId), ['111']);
    // incident was sent to 111 only: that is everyone who should get it
    expect(IncidentService.fullySent(incident), isTrue);
  });
}
