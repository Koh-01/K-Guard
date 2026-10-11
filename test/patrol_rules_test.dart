import 'package:flutter_test/flutter_test.dart';
import 'package:nfc_guard/models.dart';
import 'package:nfc_guard/patrol_rules.dart';
import 'package:nfc_guard/settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final a = Checkpoint(id: 1, tagId: 'A', name: 'Gate');
  final b = Checkpoint(id: 2, tagId: 'B', name: 'Car Park');
  final c = Checkpoint(id: 3, tagId: 'C', name: 'Lobby');
  final route = [a, b, c];

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await AppSettings.init();
  });

  test('no next checkpoint when order is not enforced', () {
    expect(PatrolRules.nextFor('Ali', route), isNull);
  });

  test('follows the order and wraps to a new round', () {
    AppSettings.enforceOrder = true;
    expect(PatrolRules.nextFor('Ali', route)!.name, 'Gate');
    PatrolRules.complete('Ali', a);
    expect(PatrolRules.nextFor('Ali', route)!.name, 'Car Park');
    PatrolRules.complete('Ali', b);
    expect(PatrolRules.nextFor('Ali', route)!.name, 'Lobby');
    expect(PatrolRules.isLast(c, route), isTrue);
    PatrolRules.complete('Ali', c);
    expect(PatrolRules.nextFor('Ali', route)!.name, 'Gate');
  });

  test('progress is per guard', () {
    AppSettings.enforceOrder = true;
    PatrolRules.complete('Ali', a);
    expect(PatrolRules.nextFor('Ali', route)!.name, 'Car Park');
    expect(PatrolRules.nextFor('Ben', route)!.name, 'Gate');
  });

  test('deleted last checkpoint restarts from the first', () {
    AppSettings.enforceOrder = true;
    PatrolRules.complete('Ali', b);
    expect(PatrolRules.nextFor('Ali', [a, c])!.name, 'Gate');
  });

  test('re-enabling or resetting clears progress', () {
    AppSettings.enforceOrder = true;
    PatrolRules.complete('Ali', b);
    AppSettings.resetOrderProgress();
    expect(PatrolRules.nextFor('Ali', route)!.name, 'Gate');
  });

  test('cooldown defaults to 1 minute', () {
    expect(AppSettings.cooldownMinutes, 1);
  });
}
