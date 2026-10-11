import 'package:flutter_test/flutter_test.dart';
import 'package:nfc_guard/location_service.dart';
import 'package:nfc_guard/models.dart';
import 'package:nfc_guard/settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  // A checkpoint in Kuala Lumpur. 0.0001° latitude ≈ 11.1 m.
  final cp =
      Checkpoint(tagId: 'A', name: 'Gate', lat: 3.139000, lng: 101.686900);
  GpsFix at(double dLatMetres, {double accuracy = 5, bool mocked = false}) =>
      GpsFix(3.139000 + dLatMetres / 111195, 101.686900, accuracy,
          mocked: mocked);

  test('distance is correct', () {
    final d = LocationService.distance(
        3.139, 101.6869, 3.139 + 100 / 111195, 101.6869);
    expect(d, closeTo(100, 0.5));
  });

  test('standing at the checkpoint is OK', () {
    final r = LocationService.evaluate(at(10), cp, 50);
    expect(r.status, 'ok');
    expect(r.distanceM, closeTo(10, 0.5));
    expect(r.failed, isFalse);
  });

  test('far away is rejected', () {
    final r = LocationService.evaluate(at(850), cp, 50);
    expect(r.status, 'far');
    expect(r.failed, isTrue);
  });

  test('GPS error gives the benefit of the doubt, but capped', () {
    // 65 m away with ±20 m accuracy: could really be 45 m -> OK.
    expect(LocationService.evaluate(at(65, accuracy: 20), cp, 50).status, 'ok');
    // 90 m away with ±80 m accuracy: leeway capped at 25 m -> still too far.
    expect(
        LocationService.evaluate(at(90, accuracy: 80), cp, 50).status, 'far');
  });

  test('very inaccurate reading counts as no GPS', () {
    expect(
        LocationService.evaluate(at(5, accuracy: 300), cp, 50).status, 'none');
    expect(LocationService.evaluate(null, cp, 50).status, 'none');
  });

  test('fake GPS is caught even when it claims to be at the checkpoint', () {
    final r = LocationService.evaluate(at(0, mocked: true), cp, 50);
    expect(r.status, 'mock');
    expect(r.failed, isTrue);
  });

  test('checkpoint without a recorded location is not checked', () {
    final noLoc = Checkpoint(tagId: 'B', name: 'Pool');
    final r = LocationService.evaluate(at(5000), noLoc, 50);
    expect(r.status, 'noref');
    expect(r.failed, isFalse);
  });

  test('labels', () {
    expect(LocationService.label('ok', 12.4), 'OK 12 m');
    expect(LocationService.label('far', 849.6), 'TOO FAR 850 m');
    expect(LocationService.label('mock', 3), 'FAKE GPS');
    expect(LocationService.label(null, null), '');
  });

  test('maps link', () {
    expect(const GpsFix(3.139, 101.6869, 5).mapsLink,
        'https://maps.google.com/?q=3.139000,101.686900');
  });

  test('owner alerts on GPS failure are on by default and can be turned off',
      () async {
    SharedPreferences.setMockInitialValues({});
    await AppSettings.init();
    expect(AppSettings.gpsAlertOwners, isTrue);
    AppSettings.gpsAlertOwners = false;
    expect(AppSettings.gpsAlertOwners, isFalse);
  });
}
