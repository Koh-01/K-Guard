import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nfc_guard/app_theme.dart';
import 'package:nfc_guard/screens/login_screen.dart';
import 'package:nfc_guard/settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> prepareSettings() async {
    SharedPreferences.setMockInitialValues({
      'site_name': 'Northgate Residence',
      'guard_accounts': jsonEncode([
        {'name': 'Alex', 'pin': '1234'},
        {'name': 'Morgan', 'pin': '1234'},
        {'name': 'Sam', 'pin': '1234'},
        {'name': 'Jordan', 'pin': '1234'},
      ]),
      'support_contact': 'K Guard support · +60 12-345 6789',
    });
    await AppSettings.init();
  }

  Widget preview(ThemeData theme) => MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: theme,
        home: Scaffold(
          appBar: AppBar(
            toolbarHeight: 68,
            title: const Text('Northgate Residence'),
            actions: const [
              IconButton(onPressed: null, icon: Icon(Icons.settings_outlined)),
              SizedBox(width: 8),
            ],
          ),
          body: LoginScreen(onLoggedIn: () {}),
        ),
      );

  testWidgets('login preview stays within a compact phone viewport',
      (tester) async {
    await prepareSettings();
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(preview(AppTheme.light()));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/login_light.png'),
    );
  });

  testWidgets('login preview stays legible in dark mode', (tester) async {
    await prepareSettings();
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(preview(AppTheme.dark()));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/login_dark.png'),
    );
  });
}
