import 'package:flutter_test/flutter_test.dart';
import 'package:nfc_guard/reminder_service.dart';
import 'package:nfc_guard/settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await AppSettings.init();
  });

  test('every 2 h from midnight', () {
    AppSettings.patrolIntervalMinutes = 120;
    AppSettings.patrolStartMinute = 0;
    expect(ReminderService.cycleStart(DateTime(2026, 9, 25, 14, 59)),
        DateTime(2026, 9, 25, 14));
    expect(ReminderService.cycleStart(DateTime(2026, 9, 25, 15, 0)),
        DateTime(2026, 9, 25, 14));
    expect(ReminderService.cycleStart(DateTime(2026, 9, 25, 16, 0)),
        DateTime(2026, 9, 25, 16));
    expect(ReminderService.cycleEnd(DateTime(2026, 9, 25, 23, 30)),
        DateTime(2026, 9, 26, 0));
  });

  test('every 3 h starting 01:00, before the first patrol of the day', () {
    AppSettings.patrolIntervalMinutes = 180;
    AppSettings.patrolStartMinute = 60;
    expect(ReminderService.cycleStart(DateTime(2026, 9, 25, 0, 30)),
        DateTime(2026, 9, 24, 22));
    expect(ReminderService.cycleStart(DateTime(2026, 9, 25, 1, 0)),
        DateTime(2026, 9, 25, 1));
    expect(ReminderService.cycleStart(DateTime(2026, 9, 25, 23, 59)),
        DateTime(2026, 9, 25, 22));
  });

  test('every 90 min lines up across midnight', () {
    AppSettings.patrolIntervalMinutes = 90;
    AppSettings.patrolStartMinute = 0;
    expect(ReminderService.cycleStart(DateTime(2026, 9, 25, 23, 0)),
        DateTime(2026, 9, 25, 22, 30));
    expect(ReminderService.cycleEnd(DateTime(2026, 9, 25, 23, 0)),
        DateTime(2026, 9, 26, 0, 0));
  });

  test('default: progress resets once a day at midnight', () {
    expect(AppSettings.patrolIntervalMinutes, 1440);
    expect(ReminderService.cycleStart(DateTime(2026, 9, 25, 23, 59)),
        DateTime(2026, 9, 25));
    expect(ReminderService.cycleEnd(DateTime(2026, 9, 25, 0, 1)),
        DateTime(2026, 9, 26));
  });

  test('24 h cycle starting 07:00 (shift change)', () {
    AppSettings.patrolStartMinute = 7 * 60;
    expect(ReminderService.cycleStart(DateTime(2026, 9, 25, 6, 59)),
        DateTime(2026, 9, 24, 7));
    expect(ReminderService.cycleStart(DateTime(2026, 9, 25, 7, 0)),
        DateTime(2026, 9, 25, 7));
  });

  test('every 12 h', () {
    AppSettings.patrolIntervalMinutes = 720;
    AppSettings.patrolStartMinute = 7 * 60;
    expect(ReminderService.cycleStart(DateTime(2026, 9, 25, 20, 0)),
        DateTime(2026, 9, 25, 19));
    expect(ReminderService.cycleStart(DateTime(2026, 9, 26, 3, 0)),
        DateTime(2026, 9, 25, 19));
  });
}
