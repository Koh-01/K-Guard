import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nfc_guard/settings.dart';
import 'package:nfc_guard/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  Future<bool?> tryPin(WidgetTester t, String pin) async {
    bool? result;
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (c) => TextButton(
            onPressed: () async => result = await askSettingsPin(c),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField), pin);
    await t.tap(find.text('OK'));
    await t.pumpAndSettle();
    return result;
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({'flutter.admin_pin': '9999'});
    await AppSettings.init();
  });

  testWidgets('default Settings PIN is 1234', (t) async {
    expect(AppSettings.settingsPin, '1234');
    expect(await tryPin(t, '1234'), isTrue);
  });

  testWidgets('wrong PIN is rejected', (t) async {
    expect(await tryPin(t, '0000'), isFalse);
  });

  testWidgets('changed PIN works, old one no longer does', (t) async {
    AppSettings.settingsPin = '5678';
    expect(await tryPin(t, '1234'), isFalse);
    expect(await tryPin(t, '5678'), isTrue);
  });

  testWidgets('Developer PIN also opens Settings', (t) async {
    AppSettings.settingsPin = '5678';
    expect(await tryPin(t, '9999'), isTrue);
  });

  test('community logo path can be saved and removed', () {
    expect(AppSettings.communityLogoPath, isNull);
    AppSettings.communityLogoPath = '/app/support/branding/community.png';
    expect(AppSettings.communityLogoPath,
        '/app/support/branding/community.png');
    AppSettings.communityLogoPath = null;
    expect(AppSettings.communityLogoPath, isNull);
  });

  test(
      'support contact: old default follows the new company name, custom text is kept',
      () async {
    SharedPreferences.setMockInitialValues(
        {'flutter.support_contact': 'Need help? Contact KTech.prod'});
    await AppSettings.init();
    expect(AppSettings.supportContact, 'Need help? Contact KTech Solution');
    AppSettings.supportContact = 'Call Ken 012-3456789';
    expect(AppSettings.supportContact, 'Call Ken 012-3456789');
  });
}
