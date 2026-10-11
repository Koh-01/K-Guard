import 'package:flutter_test/flutter_test.dart';
import 'package:nfc_guard/cleanup_service.dart';
import 'package:nfc_guard/settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await AppSettings.init();
  });

  test('disabled -> never requires photo', () {
    expect(
        List.generate(20, (_) => AppSettings.drawPhotoRequired()).any((x) => x),
        isFalse);
  });

  test('exactly M of every N check-ins require a photo, in random positions',
      () {
    AppSettings.photoProofEnabled = true;
    AppSettings.setPhotoProofRatio(2, 5);
    final patterns = <String>{};
    for (var round = 0; round < 50; round++) {
      final r = List.generate(5, (_) => AppSettings.drawPhotoRequired());
      expect(r.where((x) => x).length, 2);
      patterns.add(r.map((x) => x ? '1' : '0').join());
    }
    expect(patterns.length, greaterThan(3)); // not a fixed pattern
  });

  test('retention cutoff keeps current month plus N previous months', () {
    final now = DateTime(2026, 9, 25);
    expect(CleanupService.cutoff(3, now), DateTime(2026, 6, 1));
    expect(CleanupService.cutoff(12, now), DateTime(2025, 9, 1));
    expect(
        CleanupService.cutoff(1, DateTime(2026, 1, 5)), DateTime(2025, 12, 1));
  });
}
