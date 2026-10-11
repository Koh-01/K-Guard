import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'app_theme.dart';
import 'app_ui.dart';
import 'cleanup_service.dart';
import 'daily_report_service.dart';
import 'incident_service.dart';
import 'nfc_service.dart';
import 'outbox_service.dart';
import 'reminder_service.dart';
import 'report_service.dart';
import 'screens/home_screen.dart';
import 'screens/incidents_screen.dart';
import 'screens/login_screen.dart';
import 'screens/logs_screen.dart';
import 'screens/settings_screen.dart';
import 'settings.dart';
import 'widgets.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppSettings.init();
  runApp(const NfcGuardApp());
}

class NfcGuardApp extends StatelessWidget {
  const NfcGuardApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: AppSettings.themeMode,
      builder: (_, mode, __) => MaterialApp(
        title: 'K Guard',
        debugShowCheckedModeBanner: false,
        scaffoldMessengerKey: messengerKey,
        themeMode: mode,
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        home: const RootPage(),
      ),
    );
  }
}

class RootPage extends StatefulWidget {
  const RootPage({super.key});

  @override
  State<RootPage> createState() => _RootPageState();
}

class _RootPageState extends State<RootPage> with WidgetsBindingObserver {
  int _tab = 0;
  int _reloadKey = 0;
  Timer? _timer;
  Timer? _outboxTimer;
  int _day = DateTime.now().day;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    NfcService
        .startGuard(); // own NFC while in the foreground: no system "choose an app" popup
    _background();
    _timer = Timer.periodic(const Duration(hours: 1), (_) => _background());
    // Queued notices / proof photos are retried every minute while the app is open.
    // Every minute while open: retry queued Telegram messages, send the daily report when due.
    _outboxTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      OutboxService.process();
      DailyReportService.maybeSend();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _outboxTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      NfcService
          .stopGuard(); // hand NFC back to the system while in the background
    }
    if (state == AppLifecycleState.resumed) {
      NfcService.startGuard();
      _background();
      // Refresh "today" data after midnight. Don't rebuild on every resume: permission dialogs
      // (camera / microphone) pause and resume the app in the middle of a check-in.
      final day = DateTime.now().day;
      if (day != _day) {
        setState(() {
          _day = day;
          _reloadKey++;
        });
      }
    }
  }

  /// Monthly report, incident re-sends and old-data cleanup.
  void _background() {
    ReportService.maybeSendMonthlyReport();
    IncidentService.retryPending();
    OutboxService.process();
    DailyReportService.maybeSend();
    CleanupService.run();
    ReminderService.reschedule();
  }

  Future<void> _openSettings() async {
    if (!await askSettingsPin(context) || !mounted) return;
    await Navigator.push(
        context, MaterialPageRoute(builder: (_) => const SettingsScreen()));
    if (!mounted) return;
    setState(() => _reloadKey++);
  }

  /// SOS: opens the phone's dialer with the SOS number filled in (the guard presses Call).
  Future<void> _sos() async {
    final phone = AppSettings.sosPhone;
    if (phone.isEmpty) {
      await showMessage(context, 'SOS number not set',
          'Ask the owner to set the SOS contact in Settings → SOS.',
          icon: const Icon(Icons.sos, color: AppColors.danger, size: 56));
      return;
    }
    final uri =
        Uri(scheme: 'tel', path: phone.replaceAll(RegExp(r'[^0-9+*#]'), ''));
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && mounted) {
      await showMessage(context, 'Could not open the dialer',
          'Please call ${AppSettings.sosName.isEmpty ? '' : '${AppSettings.sosName} '}$phone manually.');
    }
  }

  Future<void> _logout() async {
    final guard = AppSettings.currentGuard;
    if (!await confirm(context, 'Log out', 'Log out $guard?')) return;
    setState(() {
      AppSettings.currentGuard = null;
      _tab = 0;
    });
  }

  Widget _loginCommunityMark() {
    final path = AppSettings.communityLogoPath;
    if (path == null || !File(path).existsSync()) {
      return const AppIconBox(Icons.shield_outlined, size: 38);
    }
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(9),
        boxShadow: [
          BoxShadow(color: AppColors.hairline(context), spreadRadius: 1),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Image.file(
        File(path),
        key: ValueKey(path),
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) =>
            const AppIconBox(Icons.shield_outlined, size: 38),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final guard = AppSettings.currentGuard;
    final settingsButton = IconButton(
        icon: const Icon(Icons.settings),
        tooltip: 'Settings',
        onPressed: _openSettings);

    if (guard == null) {
      return Scaffold(
        appBar: AppBar(
          toolbarHeight: 68,
          title: Row(
            children: [
              _loginCommunityMark(),
              const SizedBox(width: 12),
              Expanded(
                child: Text(AppSettings.siteName,
                    maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
          actions: [settingsButton, const SizedBox(width: 8)],
        ),
        body: LoginScreen(onLoggedIn: () => setState(() => _reloadKey++)),
      );
    }

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 68,
        title: Row(
          children: [
            const AppIconBox(Icons.shield_outlined, size: 38),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(AppSettings.siteName,
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  Text('On duty · $guard',
                      style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
              icon: const Icon(Icons.logout),
              tooltip: 'Log out',
              onPressed: _logout),
          settingsButton,
          const SizedBox(width: 8),
        ],
      ),
      body: switch (_tab) {
        0 => HomeScreen(key: ValueKey('home$_reloadKey')),
        1 => IncidentsScreen(key: ValueKey('incidents$_reloadKey')),
        _ => LogsScreen(key: ValueKey('logs$_reloadKey')),
      },
      bottomNavigationBar: DecoratedBox(
        decoration: BoxDecoration(
          boxShadow: [
            BoxShadow(
                color: AppColors.hairline(context),
                offset: const Offset(0, -1)),
          ],
        ),
        child: NavigationBar(
          selectedIndex: _tab,
          onDestinationSelected: (i) {
            if (i == 3) {
              _sos(); // not a page: opens the dialer
            } else {
              setState(() => _tab = i);
            }
          },
          destinations: const [
            NavigationDestination(
                icon: Icon(Icons.nfc_outlined),
                selectedIcon: Icon(Icons.nfc),
                label: 'Check In'),
            NavigationDestination(
                icon: Icon(Icons.report_problem_outlined),
                selectedIcon: Icon(Icons.report_problem),
                label: 'Incidents'),
            NavigationDestination(
                icon: Icon(Icons.receipt_long_outlined),
                selectedIcon: Icon(Icons.receipt_long),
                label: 'Logs'),
            NavigationDestination(
              icon: Icon(Icons.sos_outlined, color: AppColors.danger),
              selectedIcon: Icon(Icons.sos, color: AppColors.danger),
              label: 'SOS',
            ),
          ],
        ),
      ),
    );
  }
}
