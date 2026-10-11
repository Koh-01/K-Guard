import 'package:flutter_test/flutter_test.dart';
import 'package:nfc_guard/report_service.dart';
import 'package:nfc_guard/settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

String prevMonth() {
  final n = DateTime.now();
  return ReportService.monthKey(
      DateTime(n.year, n.month - 1).year, DateTime(n.year, n.month - 1).month);
}

void main() {
  test(
      'legacy month is migrated once and cleared; new owners are not back-filled',
      () async {
    SharedPreferences.setMockInitialValues({
      'flutter.bot_token': 'x',
      'flutter.chat_id': '111',
      'flutter.last_auto_report_month':
          prevMonth(), // already sent under the old version
    });
    await AppSettings.init();

    await ReportService
        .maybeSendMonthlyReport(); // nothing due -> no network call
    expect(AppSettings.autoReportSent, {'111': prevMonth()});
    expect(AppSettings.legacyLastAutoReportMonth, isNull);

    // A new owner added later must not inherit the old value.
    AppSettings.owners = [...AppSettings.owners, const Owner('222', 'New')];
    await ReportService.maybeSendMonthlyReport();
    expect(AppSettings.autoReportSent['222'], prevMonth());
  });

  test('auto monthly report skips owners who switched it off', () async {
    SharedPreferences.setMockInitialValues({
      'flutter.bot_token': 'x',
      'flutter.owners':
          '[{"chat_id":"111","name":"A"},{"chat_id":"222","name":"B","monthly_report":false}]',
    });
    await AppSettings.init();
    await ReportService
        .maybeSendMonthlyReport(); // first run: records start month, sends nothing
    expect(AppSettings.autoReportSent.keys,
        ['111']); // 222 is not tracked: it never gets it
  });
}
