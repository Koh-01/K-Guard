import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../app_theme.dart';
import '../app_ui.dart';
import '../report_service.dart';
import '../settings.dart';
import '../telegram_service.dart';
import '../daily_report_service.dart';
import '../widgets.dart';
import 'developer_settings_screen.dart';

/// Level-1 settings for owners / supervisors (requires the Settings PIN).
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _busy = false;

  Future<void> _pickCommunityLogo() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1024,
      maxHeight: 1024,
      imageQuality: 90,
    );
    if (picked == null || !mounted) return;

    setState(() => _busy = true);
    try {
      final support = await getApplicationSupportDirectory();
      final branding = Directory(p.join(support.path, 'branding'));
      await branding.create(recursive: true);
      final rawExtension = p.extension(picked.path).toLowerCase();
      final extension = rawExtension.isEmpty ? '.jpg' : rawExtension;
      final destination = p.join(branding.path,
          'community_logo_${DateTime.now().millisecondsSinceEpoch}$extension');
      await File(picked.path).copy(destination);

      final previous = AppSettings.communityLogoPath;
      AppSettings.communityLogoPath = destination;
      if (previous != null && previous != destination) {
        try {
          await File(previous).delete();
        } catch (_) {}
      }
      if (mounted) {
        setState(() {});
        toast(context, 'Community logo updated');
      }
    } catch (e) {
      if (mounted) {
        await showMessage(context, 'Could not save logo', '$e');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _removeCommunityLogo() async {
    final path = AppSettings.communityLogoPath;
    if (path == null ||
        !await confirm(context, 'Remove community logo',
            'Use the default K Guard icon on the login page?')) {
      return;
    }
    AppSettings.communityLogoPath = null;
    try {
      await File(path).delete();
    } catch (_) {}
    if (mounted) setState(() {});
  }

  Widget _communityLogoPreview() {
    final path = AppSettings.communityLogoPath;
    if (path != null && File(path).existsSync()) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(9),
        child: Image.file(
          File(path),
          key: ValueKey(path),
          width: 44,
          height: 44,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) =>
              const AppIconBox(Icons.apartment_outlined, size: 44),
        ),
      );
    }
    return const AppIconBox(Icons.apartment_outlined, size: 44);
  }

  // ---------- Guard accounts ----------

  Future<void> _addGuard() async {
    if (AppSettings.guards.length >= AppSettings.maxGuards) {
      await showMessage(
          context,
          'Guard limit reached',
          'A maximum of ${AppSettings.maxGuards} guard accounts is allowed.\n'
              'Delete an existing guard before adding a new one.');
      return;
    }
    final result = await showDialog<Guard>(
        context: context, builder: (_) => const _GuardDialog());
    if (result == null || !mounted) return;
    if (AppSettings.guards
        .any((g) => g.name.toLowerCase() == result.name.toLowerCase())) {
      toast(context, 'A guard named "${result.name}" already exists');
      return;
    }
    setState(() => AppSettings.guards = [...AppSettings.guards, result]);
  }

  Future<void> _resetGuardPin(Guard g) async {
    final pin =
        await askPin(context, 'New PIN for ${g.name}', hint: '4–6 digits');
    if (pin == null || !mounted) return;
    if (pin.length < 4) {
      toast(context, 'PIN must be 4–6 digits');
      return;
    }
    AppSettings.guards = [
      for (final x in AppSettings.guards)
        x.name == g.name ? Guard(g.name, pin) : x
    ];
    toast(context, 'PIN updated for ${g.name}');
  }

  Future<void> _removeGuard(Guard g) async {
    if (!await confirm(context, 'Delete guard',
        'Delete the account of "${g.name}"? Their past check-in records are kept.')) {
      return;
    }
    setState(() => AppSettings.guards =
        AppSettings.guards.where((x) => x.name != g.name).toList());
  }

  // ---------- Telegram ----------

  void _saveOwner(Owner o) {
    final owners = AppSettings.owners;
    if (owners.any((x) => x.chatId == o.chatId)) {
      toast(context, '${o.name} is already an owner');
      return;
    }
    setState(() => AppSettings.owners = [...owners, o]);
    toast(context, 'Added ${o.name}');
  }

  /// Adds an owner by picking from chats that recently messaged the bot.
  Future<void> _addOwner() async {
    if (AppSettings.botToken.isEmpty) {
      await showMessage(context, 'Bot not set up',
          'The Telegram Bot Token has not been set. Please contact the developer.');
      return;
    }
    setState(() => _busy = true);
    List<({String id, String title})> chats;
    try {
      final existing = AppSettings.owners.map((o) => o.chatId).toSet();
      chats = (await TelegramService.recentChats(AppSettings.botToken))
          .where((c) => !existing.contains(c.id))
          .toList();
    } catch (e) {
      if (mounted) await showMessage(context, 'Failed', '$e');
      return;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (!mounted) return;

    const manual = '__manual__';
    final picked = await showDialog<String>(
      context: context,
      builder: (c) => SimpleDialog(
        title: const Text('Add owner'),
        children: [
          if (chats.isEmpty)
            const Padding(
              padding: EdgeInsets.fromLTRB(24, 0, 24, 12),
              child: Text(
                  'No new chats found. Ask the owner to open your bot in Telegram and press '
                  'Start (or send any message), then try again.'),
            ),
          for (final chat in chats)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(c, chat.id),
              child: ListTile(
                leading: const Icon(Icons.person_outline),
                title: Text(chat.title),
                subtitle: Text(chat.id),
              ),
            ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(c, manual),
            child: const ListTile(
                leading: Icon(Icons.keyboard),
                title: Text('Enter Chat ID manually')),
          ),
        ],
      ),
    );
    if (picked == null || !mounted) return;

    if (picked == manual) {
      final id = await editText(context, 'Owner Chat ID',
          hint: 'e.g. 123456789',
          keyboardType: const TextInputType.numberWithOptions(signed: true));
      if (id == null || id.isEmpty || !mounted) return;
      final name = await editText(context, 'Owner name', hint: 'e.g. Mr Tan');
      if (!mounted) return;
      _saveOwner(Owner(id, name == null || name.isEmpty ? 'Owner' : name));
    } else {
      final chat = chats.firstWhere((c) => c.id == picked);
      _saveOwner(Owner(chat.id, chat.title.isEmpty ? 'Owner' : chat.title));
    }
  }

  Future<void> _renameOwner(Owner o) async {
    final name = await editText(context, 'Owner name', initial: o.name);
    if (name == null || name.isEmpty) return;
    setState(() => AppSettings.owners = [
          for (final x in AppSettings.owners)
            x.chatId == o.chatId ? x.copyWith(name: name) : x
        ]);
  }

  void _updateOwner(Owner updated) {
    setState(() => AppSettings.owners = [
          for (final x in AppSettings.owners)
            x.chatId == updated.chatId ? updated : x
        ]);
  }

  String _ownerSummary(Owner o) {
    final alerts = [
      if (o.notifyCheckins) 'check-ins',
      if (o.gpsAlerts) 'GPS',
      if (o.incidentReports) 'incidents',
      if (o.proofPhotos) 'photos',
    ];
    final reports = [
      if (o.dailyReport) 'daily',
      if (o.monthlyReport) 'monthly',
    ];
    final parts = [
      if (alerts.isNotEmpty) 'Alerts: ${alerts.join(', ')}',
      if (reports.isNotEmpty) 'Reports: ${reports.join(', ')}',
    ];
    return parts.isEmpty ? 'Receives nothing' : parts.join('  ·  ');
  }

  /// Per-owner options: what this owner receives, rename, remove.
  Future<void> _editOwner(Owner owner) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled:
          true, // grow to fit all options instead of stopping at half height
      builder: (c) => StatefulBuilder(builder: (c, setSheet) {
        final o = AppSettings.owners
            .firstWhere((x) => x.chatId == owner.chatId, orElse: () => owner);
        return SafeArea(
          child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
            ListTile(
              leading: const Icon(Icons.person),
              title: Text(o.name, style: Theme.of(c).textTheme.titleMedium),
              subtitle: Text('Chat ID ${o.chatId}'),
            ),
            _sheetHeader(c, 'Alerts'),
            _ownerSwitch(
              icon: Icons.notifications_active_outlined,
              title: 'Check-in alerts',
              subtitle: 'A message on every check-in',
              value: o.notifyCheckins,
              onChanged: (v) => o.copyWith(notifyCheckins: v),
              setSheet: setSheet,
            ),
            _ownerSwitch(
              icon: Icons.wrong_location_outlined,
              title: 'GPS alerts',
              subtitle:
                  'When a check-in fails the GPS check (possible cheating)',
              disabledNote:
                  AppSettings.gpsMode == 'off' || !AppSettings.gpsAlertOwners
                      ? 'Turned off for everyone in Developer settings'
                      : null,
              value: o.gpsAlerts,
              onChanged: (v) => o.copyWith(gpsAlerts: v),
              setSheet: setSheet,
            ),
            _ownerSwitch(
              icon: Icons.report_problem_outlined,
              title: 'Incident reports',
              subtitle: 'Incidents with their photos, video and voice notes',
              value: o.incidentReports,
              onChanged: (v) => o.copyWith(incidentReports: v),
              setSheet: setSheet,
            ),
            _ownerSwitch(
              icon: Icons.photo_camera_outlined,
              title: 'Proof photos',
              subtitle: 'Random photo proofs as soon as guards take them',
              disabledNote:
                  !AppSettings.photoProofEnabled || !AppSettings.sendProofPhotos
                      ? 'Turned off for everyone in Developer settings'
                      : null,
              value: o.proofPhotos,
              onChanged: (v) => o.copyWith(proofPhotos: v),
              setSheet: setSheet,
            ),
            _sheetHeader(c, 'Reports'),
            _ownerSwitch(
              icon: Icons.today_outlined,
              title: 'Daily report',
              subtitle:
                  'Last 24 hours, every day at ${_hm(AppSettings.dailyReportMinute)}',
              value: o.dailyReport,
              onChanged: (v) {
                if (v) DailyReportService.startFromNext(o);
                return o.copyWith(dailyReport: v);
              },
              setSheet: setSheet,
            ),
            _ownerSwitch(
              icon: Icons.calendar_month_outlined,
              title: 'Monthly report',
              subtitle: "Last month's summary, PDF with photos and CSV",
              value: o.monthlyReport,
              onChanged: (v) => o.copyWith(monthlyReport: v),
              setSheet: setSheet,
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.edit),
              title: const Text('Rename'),
              onTap: () async {
                Navigator.pop(c);
                await _renameOwner(o);
              },
            ),
            ListTile(
              leading:
                  const Icon(Icons.delete_outline, color: AppColors.danger),
              title: const Text('Remove owner',
                  style: TextStyle(color: AppColors.danger)),
              onTap: () async {
                Navigator.pop(c);
                await _removeOwner(o);
              },
            ),
          ])),
        );
      }),
    );
  }

  Widget _sheetHeader(BuildContext c, String text) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(text, style: Theme.of(c).textTheme.titleMedium),
        ),
      );

  /// One on/off option in the owner sheet. [onChanged] returns the updated owner.
  Widget _ownerSwitch({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required Owner Function(bool v) onChanged,
    required StateSetter setSheet,
    String? disabledNote,
  }) =>
      SwitchListTile(
        secondary: Icon(icon),
        title: Text(title),
        subtitle: Text(disabledNote ?? subtitle,
            style: disabledNote == null
                ? null
                : const TextStyle(color: AppColors.warning)),
        value: value,
        onChanged: (v) {
          _updateOwner(onChanged(v));
          setSheet(() {});
        },
      );

  String _hm(int m) =>
      '${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}';

  Future<void> _editDailyTime() async {
    final m = AppSettings.dailyReportMinute;
    final t = await showTimePicker(
      context: context,
      helpText: 'Send the daily report at',
      initialTime: TimeOfDay(hour: m ~/ 60, minute: m % 60),
    );
    if (t == null) return;
    setState(() => AppSettings.dailyReportMinute = t.hour * 60 + t.minute);
    // Owners who already got today's report keep it; the new time applies from the next report.
    for (final o in AppSettings.owners.where((o) => o.dailyReport)) {
      DailyReportService.startFromNext(o);
    }
  }

  Future<void> _editSos() async {
    final name = await editText(context, 'SOS contact name',
        initial: AppSettings.sosName,
        hint: 'e.g. Mr Tan (owner), Police, Security manager');
    if (name == null || !mounted) return;
    final phone = await editText(context, 'SOS phone number',
        initial: AppSettings.sosPhone,
        hint: 'e.g. +60123456789',
        keyboardType: TextInputType.phone);
    if (phone == null) return;
    setState(() {
      AppSettings.sosName = name;
      AppSettings.sosPhone = phone;
    });
  }

  Future<void> _removeOwner(Owner o) async {
    if (!await confirm(context, 'Remove owner',
        '${o.name} will no longer receive patrol reports.')) {
      return;
    }
    setState(() => AppSettings.owners =
        AppSettings.owners.where((x) => x.chatId != o.chatId).toList());
  }

  Future<void> _test() async {
    setState(() => _busy = true);
    try {
      await TelegramService.sendMessage(
          '🔔 ${AppSettings.siteName} patrol check-in system is connected. Patrol logs will be sent via this bot.');
      if (mounted) toast(context, 'Test message sent');
    } catch (e) {
      if (mounted) await showMessage(context, 'Send failed', '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _sendLastMonth() async {
    final now = DateTime.now();
    final prev = DateTime(now.year, now.month - 1);
    setState(() => _busy = true);
    try {
      await ReportService.sendMonthReport(prev.year, prev.month,
          sentBy: AppSettings.currentGuard == null
              ? 'Sent manually'
              : 'Sent manually by ${AppSettings.currentGuard}');
      if (mounted) toast(context, "Last month's report sent");
    } catch (e) {
      if (mounted) await showMessage(context, 'Send failed', '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _changeSettingsPin() async {
    final a = await askPin(context, 'New Settings PIN', hint: '4–6 digits');
    if (a == null || !mounted) return;
    if (a.length < 4) {
      toast(context, 'PIN must be 4–6 digits');
      return;
    }
    final b = await askPin(context, 'Confirm new Settings PIN');
    if (!mounted) return;
    if (a != b) {
      toast(context, 'PINs do not match');
      return;
    }
    setState(() => AppSettings.settingsPin = a);
    toast(context, 'Settings PIN changed');
  }

  Future<void> _openDeveloper() async {
    if (!await askAdminPin(context) || !mounted) return;
    await Navigator.push(context,
        MaterialPageRoute(builder: (_) => const DeveloperSettingsScreen()));
    if (mounted) setState(() {});
  }

  Widget _header(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 28, 16, 10),
        child: AppSectionHeader(text),
      );

  @override
  Widget build(BuildContext context) {
    final guards = AppSettings.guards;
    final full = guards.length >= AppSettings.maxGuards;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        bottom: _busy
            ? const PreferredSize(
                preferredSize: Size.fromHeight(4),
                child: LinearProgressIndicator())
            : null,
      ),
      body: AbsorbPointer(
        absorbing: _busy,
        child: ListView(
          children: [
            _header('Appearance'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: SegmentedButton<ThemeMode>(
                segments: const [
                  ButtonSegment(
                      value: ThemeMode.system,
                      icon: Icon(Icons.brightness_auto),
                      label: Text('System')),
                  ButtonSegment(
                      value: ThemeMode.light,
                      icon: Icon(Icons.light_mode),
                      label: Text('Light')),
                  ButtonSegment(
                      value: ThemeMode.dark,
                      icon: Icon(Icons.dark_mode),
                      label: Text('Dark')),
                ],
                selected: {AppSettings.themeMode.value},
                onSelectionChanged: (s) =>
                    setState(() => AppSettings.setThemeMode(s.first)),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: AppSurface(
                child: ListTile(
                  leading: _communityLogoPreview(),
                  title: const Text('Community logo'),
                  subtitle: Text(AppSettings.communityLogoPath == null
                      ? 'Upload a logo for the login page'
                      : 'Tap to replace the current logo'),
                  trailing: AppSettings.communityLogoPath == null
                      ? const Icon(Icons.chevron_right)
                      : IconButton(
                          tooltip: 'Remove logo',
                          onPressed: _removeCommunityLogo,
                          icon: const Icon(Icons.delete_outline),
                        ),
                  onTap: _pickCommunityLogo,
                ),
              ),
            ),
            _header(
                'Guard accounts (${guards.length}/${AppSettings.maxGuards})'),
            for (final g in guards)
              ListTile(
                leading: const Icon(Icons.person),
                title: Text(g.name),
                subtitle: const Text('Tap to reset PIN'),
                onTap: () => _resetGuardPin(g),
                trailing: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => _removeGuard(g)),
              ),
            ListTile(
              leading: Icon(Icons.person_add,
                  color: full
                      ? Theme.of(context).colorScheme.onSurfaceVariant
                      : null),
              title: Text('Add guard',
                  style: TextStyle(
                      color: full
                          ? Theme.of(context).colorScheme.onSurfaceVariant
                          : null)),
              subtitle: full
                  ? const Text(
                      'Limit reached — delete a guard to add a new one')
                  : null,
              onTap: _addGuard,
            ),
            _header('Telegram owners (${AppSettings.owners.length})'),
            for (final o in AppSettings.owners)
              ListTile(
                leading: const Icon(Icons.person_outline),
                title: Text(o.name),
                subtitle: Text(_ownerSummary(o)),
                onTap: () => _editOwner(o),
                trailing: const Icon(Icons.chevron_right),
              ),
            ListTile(
              leading: const Icon(Icons.person_add_alt),
              title: const Text('Add owner'),
              subtitle: AppSettings.owners.isEmpty
                  ? const Text('No owners yet — reports cannot be sent')
                  : null,
              onTap: _addOwner,
            ),
            ListTile(
              leading: const Icon(Icons.send),
              title: const Text('Send test message to all owners'),
              enabled: AppSettings.telegramConfigured,
              onTap: _test,
            ),
            ListTile(
              leading: const Icon(Icons.schedule_send_outlined),
              title: const Text('Daily report time'),
              subtitle:
                  Text('${_hm(AppSettings.dailyReportMinute)} every day · '
                      'tap an owner above to choose who receives it'),
              onTap: _editDailyTime,
            ),
            ListTile(
              leading: const Icon(Icons.history),
              title: const Text("Send last month's report now"),
              enabled: AppSettings.telegramConfigured,
              onTap: _sendLastMonth,
            ),
            _header('SOS'),
            ListTile(
              leading: const Icon(Icons.sos, color: AppColors.danger),
              title: const Text('SOS button calls'),
              subtitle: Text(AppSettings.sosPhone.isEmpty
                  ? 'Not set — the SOS button will not work'
                  : '${AppSettings.sosName.isEmpty ? 'SOS contact' : AppSettings.sosName} · ${AppSettings.sosPhone}'),
              onTap: _editSos,
            ),
            _header('Security'),
            ListTile(
              leading: const Icon(Icons.lock_outline),
              title: const Text('Change Settings PIN'),
              subtitle:
                  AppSettings.settingsPin == AppSettings.defaultSettingsPin
                      ? const Text(
                          'Still using the default PIN 1234 — please change it',
                          style: TextStyle(color: AppColors.danger))
                      : const Text('Needed to open this Settings page'),
              onTap: _changeSettingsPin,
            ),
            const Divider(height: 40),
            ListTile(
              leading: const Icon(Icons.developer_mode),
              title: const Text('Developer settings'),
              subtitle: const Text('Requires developer PIN'),
              trailing: const Icon(Icons.lock_outline),
              onTap: _openDeveloper,
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}

/// Dialog to create a guard account (name + PIN).
class _GuardDialog extends StatefulWidget {
  const _GuardDialog();

  @override
  State<_GuardDialog> createState() => _GuardDialogState();
}

class _GuardDialogState extends State<_GuardDialog> {
  final _name = TextEditingController();
  final _pin = TextEditingController();
  String? _error;

  void _submit() {
    final name = _name.text.trim();
    final pin = _pin.text;
    if (name.isEmpty) {
      setState(() => _error = 'Enter a name');
    } else if (pin.length < 4) {
      setState(() => _error = 'PIN must be 4–6 digits');
    } else {
      Navigator.pop(context, Guard(name, pin));
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add guard'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _name,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Name'),
          ),
          TextField(
            controller: _pin,
            obscureText: true,
            keyboardType: TextInputType.number,
            maxLength: 6,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(labelText: 'PIN (4–6 digits)'),
            onSubmitted: (_) => _submit(),
          ),
          if (_error != null)
            Text(_error!, style: const TextStyle(color: AppColors.danger)),
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        FilledButton(onPressed: _submit, child: const Text('Add')),
      ],
    );
  }
}
