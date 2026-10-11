import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../app_theme.dart';
import '../app_ui.dart';
import '../cleanup_service.dart';
import '../reminder_service.dart';
import '../settings.dart';
import '../widgets.dart';
import 'checkpoints_screen.dart';

/// Level-2 settings: developer only (requires the developer PIN).
class DeveloperSettingsScreen extends StatefulWidget {
  const DeveloperSettingsScreen({super.key});

  @override
  State<DeveloperSettingsScreen> createState() =>
      _DeveloperSettingsScreenState();
}

class _DeveloperSettingsScreenState extends State<DeveloperSettingsScreen> {
  String? _photoSize;

  @override
  void initState() {
    super.initState();
    _loadPhotoSize();
  }

  String _mask(String token) => token.length <= 10
      ? token
      : '${token.substring(0, 6)}…${token.substring(token.length - 4)}';

  Future<void> _editSiteName() async {
    final v = await editText(context, 'Property / site name',
        initial: AppSettings.siteName);
    if (v != null && v.isNotEmpty) setState(() => AppSettings.siteName = v);
  }

  Future<void> _editToken() async {
    final v = await editText(context, 'Telegram Bot Token',
        initial: AppSettings.botToken, hint: 'Get it from @BotFather');
    if (v != null) setState(() => AppSettings.botToken = v);
  }

  Future<void> _editPhotoRatio() async {
    final result = await showDialog<(int, int)>(
        context: context, builder: (_) => const _PhotoRatioDialog());
    if (result == null) return;
    setState(() => AppSettings.setPhotoProofRatio(result.$1, result.$2));
  }

  static const _retentionOptions = [0, 1, 2, 3, 6, 12];

  String _retentionLabel(int m) => m == 0
      ? 'Never delete'
      : 'Keep $m month${m > 1 ? 's' : ''} + current month';

  Future<void> _loadPhotoSize() async {
    final b = await CleanupService.photoBytes();
    if (mounted) setState(() => _photoSize = CleanupService.formatBytes(b));
  }

  Future<void> _editRetention() async {
    final picked = await showDialog<int>(
      context: context,
      builder: (c) => SimpleDialog(
        title: const Text('Auto-delete old data'),
        children: [
          for (final m in _retentionOptions)
            ListTile(
              leading: Icon(m == AppSettings.retentionMonths
                  ? Icons.radio_button_checked
                  : Icons.radio_button_off),
              title: Text(_retentionLabel(m)),
              onTap: () => Navigator.pop(c, m),
            ),
        ],
      ),
    );
    if (picked == null || picked == AppSettings.retentionMonths || !mounted) {
      return;
    }
    if (picked > 0) {
      final cut =
          DateFormat('d MMM yyyy').format(CleanupService.cutoff(picked));
      if (!await confirm(
          context,
          'Enable auto-delete?',
          'Check-in logs, incidents and all their photos / videos from before $cut will be permanently deleted, '
              'now and automatically from now on.\n\nMake sure those months have been sent to the owners.')) {
        return;
      }
    }
    setState(() => AppSettings.retentionMonths = picked);
    await _cleanNow(silent: true);
  }

  Future<void> _cleanNow({bool silent = false}) async {
    final keep = AppSettings.retentionMonths;
    if (keep == 0) {
      if (!silent) {
        toast(context,
            'Auto-delete is off — choose how many months to keep first');
      }
      return;
    }
    final n = await CleanupService.run();
    await _loadPhotoSize();
    if (mounted) {
      toast(context,
          n == 0 ? 'Nothing to delete' : 'Deleted $n old check-in record(s)');
    }
  }

  Future<void> _clearAll() async {
    if (!await confirm(
            context,
            'Clear all log data',
            'This permanently deletes EVERY check-in record, incident report, photo, video and voice note on this phone. '
                'It cannot be undone.\n\nSend any reports you still need to the owners first.\n\n'
                'Checkpoints, guard accounts, owners and settings are kept.') ||
        !mounted) {
      return;
    }
    final typed = await editText(
      context,
      'Clear ALL log data?',
      hint: 'Type DELETE to confirm',
    );
    if (typed == null || !mounted) return;
    if (typed != 'DELETE') {
      toast(context, 'Not cleared — you must type DELETE');
      return;
    }
    final n = await CleanupService.clearAll();
    await _loadPhotoSize();
    if (mounted) {
      toast(context, 'Deleted $n check-in record(s), all incidents and media');
    }
  }

  static const _cooldownOptions = [1, 5, 10, 15, 30, 60, 120];

  String _minutes(int m) => m == 1440
      ? '24 hours (once a day)'
      : m < 60
          ? '$m min'
          : m % 60 == 0
              ? '${m ~/ 60} hour${m >= 120 ? 's' : ''}'
              : '${m ~/ 60} h ${m % 60} min';

  Future<void> _editCooldown() async {
    final picked = await showDialog<int>(
      context: context,
      builder: (c) => SimpleDialog(
        title: const Text('Check-in cooldown'),
        children: [
          for (final m in _cooldownOptions)
            ListTile(
              leading: Icon(m == AppSettings.cooldownMinutes
                  ? Icons.radio_button_checked
                  : Icons.radio_button_off),
              title: Text(_minutes(m)),
              onTap: () => Navigator.pop(c, m),
            ),
        ],
      ),
    );
    if (picked != null) setState(() => AppSettings.cooldownMinutes = picked);
  }

  static const _intervalOptions = [
    30,
    60,
    90,
    120,
    180,
    240,
    360,
    480,
    720,
    1440
  ];

  String _hm(int minuteOfDay) =>
      '${(minuteOfDay ~/ 60).toString().padLeft(2, '0')}:${(minuteOfDay % 60).toString().padLeft(2, '0')}';

  Future<void> _applyReminders() async {
    if (AppSettings.reminderEnabled) await ReminderService.requestPermissions();
    await ReminderService.reschedule();
  }

  Future<void> _editInterval() async {
    final picked = await showDialog<int>(
      context: context,
      builder: (c) => SimpleDialog(
        title: const Text('Progress resets every'),
        children: [
          for (final m in _intervalOptions)
            ListTile(
              leading: Icon(m == AppSettings.patrolIntervalMinutes
                  ? Icons.radio_button_checked
                  : Icons.radio_button_off),
              title: Text(_minutes(m)),
              onTap: () => Navigator.pop(c, m),
            ),
        ],
      ),
    );
    if (picked == null) return;
    setState(() => AppSettings.patrolIntervalMinutes = picked);
    await _applyReminders();
  }

  Future<void> _editStart() async {
    final m = AppSettings.patrolStartMinute;
    final t = await showTimePicker(
      context: context,
      helpText: 'First cycle of the day starts at',
      initialTime: TimeOfDay(hour: m ~/ 60, minute: m % 60),
    );
    if (t == null) return;
    setState(() => AppSettings.patrolStartMinute = t.hour * 60 + t.minute);
    await _applyReminders();
  }

  static const _gpsModes = {
    'off': ('Off', 'No GPS check'),
    'flag': (
      'Flag only',
      'Record the check-in, mark it red in reports and alert owners'
    ),
    'block': ('Block check-in', 'Refuse the check-in and alert owners'),
  };
  static const _radiusOptions = [20, 30, 50, 100, 200];

  Future<void> _editGpsMode() async {
    final picked = await showDialog<String>(
      context: context,
      builder: (c) => SimpleDialog(
        title: const Text('When the guard is too far from the checkpoint'),
        children: [
          for (final e in _gpsModes.entries)
            ListTile(
              leading: Icon(e.key == AppSettings.gpsMode
                  ? Icons.radio_button_checked
                  : Icons.radio_button_off),
              title: Text(e.value.$1),
              subtitle: Text(e.value.$2),
              onTap: () => Navigator.pop(c, e.key),
            ),
        ],
      ),
    );
    if (picked != null) setState(() => AppSettings.gpsMode = picked);
  }

  Future<void> _editRadius() async {
    final picked = await showDialog<int>(
      context: context,
      builder: (c) => SimpleDialog(
        title: const Text('Allowed distance from checkpoint'),
        children: [
          for (final m in _radiusOptions)
            ListTile(
              leading: Icon(m == AppSettings.gpsRadiusM
                  ? Icons.radio_button_checked
                  : Icons.radio_button_off),
              title: Text('$m m'),
              onTap: () => Navigator.pop(c, m),
            ),
        ],
      ),
    );
    if (picked != null) setState(() => AppSettings.gpsRadiusM = picked);
  }

  Future<void> _resetOrder() async {
    if (!await confirm(context, 'Reset patrol progress',
        'Every guard will start again from checkpoint 1.')) {
      return;
    }
    AppSettings.resetOrderProgress();
    if (mounted) toast(context, 'Patrol progress reset');
  }

  Future<void> _editSupport() async {
    final v = await editText(
      context,
      'Support contact (login page)',
      initial: AppSettings.supportContact,
      hint:
          'e.g. KTech Solution\nWhatsApp: +60 12-345 6789\nEmail: support@example.com',
      multiline: true,
    );
    if (v != null) setState(() => AppSettings.supportContact = v);
  }

  Future<void> _resetSettingsPin() async {
    if (!await confirm(context, 'Reset Settings PIN',
        'The Settings PIN (level-1 settings) will be reset to 1234.')) {
      return;
    }
    setState(() => AppSettings.settingsPin = AppSettings.defaultSettingsPin);
    if (mounted) toast(context, 'Settings PIN reset to 1234');
  }

  Future<void> _changePin() async {
    final a = await askPin(context, 'New developer PIN', hint: '4–6 digits');
    if (a == null || !mounted) return;
    if (a.length < 4) {
      toast(context, 'PIN must be 4–6 digits');
      return;
    }
    final b = await askPin(context, 'Confirm new developer PIN');
    if (!mounted) return;
    if (a != b) {
      toast(context, 'PINs do not match');
      return;
    }
    setState(() => AppSettings.adminPin = a);
    toast(context, 'Developer PIN changed');
  }

  Widget _header(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 28, 16, 10),
        child: AppSectionHeader(text),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Developer Settings')),
      body: ListView(
        children: [
          _header('Property'),
          ListTile(
            leading: const Icon(Icons.apartment),
            title: const Text('Property / site name'),
            subtitle: Text(AppSettings.siteName),
            onTap: _editSiteName,
          ),
          ListTile(
            leading: const Icon(Icons.location_on),
            title: const Text('Checkpoints'),
            subtitle: const Text('Register patrol points by scanning NFC tags'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const CheckpointsScreen())),
          ),
          _header('Telegram'),
          ListTile(
            leading: const Icon(Icons.smart_toy_outlined),
            title: const Text('Bot Token'),
            subtitle: Text(AppSettings.botToken.isEmpty
                ? 'Not set'
                : _mask(AppSettings.botToken)),
            onTap: _editToken,
          ),
          SwitchListTile(
            secondary: const Icon(Icons.event_repeat),
            title: const Text('Monthly auto report'),
            subtitle: const Text(
                "After the 1st of each month, send last month's report to owners with Monthly report on"),
            value: AppSettings.autoMonthlyReport,
            onChanged: (v) => setState(() => AppSettings.autoMonthlyReport = v),
          ),
          _header('Patrol cycle'),
          ListTile(
            leading: const Icon(Icons.repeat),
            title: const Text('Progress resets every'),
            subtitle: Text(_minutes(AppSettings.patrolIntervalMinutes)),
            onTap: _editInterval,
          ),
          ListTile(
            leading: const Icon(Icons.schedule),
            title: const Text('Cycle starts at'),
            subtitle: Text('${_hm(AppSettings.patrolStartMinute)} · '
                'current cycle ends ${DateFormat('HH:mm').format(ReminderService.cycleEnd())}'),
            onTap: _editStart,
          ),
          SwitchListTile(
            secondary: const Icon(Icons.alarm),
            title: const Text('Alarm at start of each cycle'),
            subtitle: const Text(
                'Rings to remind the guard on duty to start patrolling'),
            value: AppSettings.reminderEnabled,
            onChanged: (v) async {
              setState(() => AppSettings.reminderEnabled = v);
              await _applyReminders();
            },
          ),
          _header('GPS location check'),
          ListTile(
            leading: const Icon(Icons.location_on_outlined),
            title: const Text('GPS check'),
            subtitle: Text(
                '${_gpsModes[AppSettings.gpsMode]!.$1} — ${_gpsModes[AppSettings.gpsMode]!.$2}'),
            onTap: _editGpsMode,
          ),
          ListTile(
            enabled: AppSettings.gpsMode != 'off',
            leading: const Icon(Icons.social_distance),
            title: const Text('Allowed distance'),
            subtitle: Text(
                '${AppSettings.gpsRadiusM} m from the checkpoint\'s recorded location'),
            onTap: _editRadius,
          ),
          SwitchListTile(
            secondary: const Icon(Icons.notification_important_outlined),
            title: const Text('Alert owners'),
            subtitle: const Text(
                'Send owners an instant Telegram alert (with map link) when a check-in fails the '
                'GPS check. Rejected check-ins are always listed in the monthly report.'),
            value: AppSettings.gpsAlertOwners,
            onChanged: AppSettings.gpsMode == 'off'
                ? null
                : (v) => setState(() => AppSettings.gpsAlertOwners = v),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(72, 0, 16, 8),
            child: Text(
              'Each checkpoint needs its GPS location: it is recorded when you register a tag, '
              'or stand at the checkpoint and use Checkpoints → ⋮ → Set location here. '
              'Checkpoints without a location are not GPS-checked.',
              style: TextStyle(fontSize: 12),
            ),
          ),
          _header('Patrol rules'),
          ListTile(
            leading: const Icon(Icons.timer_outlined),
            title: const Text('Check-in cooldown'),
            subtitle: Text(
                'A guard can check in at the same checkpoint only once every ${_minutes(AppSettings.cooldownMinutes)}'),
            onTap: _editCooldown,
          ),
          SwitchListTile(
            secondary: const Icon(Icons.format_list_numbered),
            title: const Text('Enforce patrol order'),
            subtitle: const Text(
                'Guards must scan checkpoints in order (set the order in Checkpoints by dragging)'),
            value: AppSettings.enforceOrder,
            onChanged: (v) => setState(() => AppSettings.enforceOrder = v),
          ),
          ListTile(
            enabled: AppSettings.enforceOrder,
            leading: const Icon(Icons.restart_alt),
            title: const Text('Reset patrol progress'),
            subtitle: const Text('All guards start again from checkpoint 1'),
            onTap: _resetOrder,
          ),
          _header('Photo proof'),
          SwitchListTile(
            secondary: const Icon(Icons.photo_camera_outlined),
            title: const Text('Random photo proof'),
            subtitle: const Text(
                'Guards must take a live camera photo on randomly selected check-ins'),
            value: AppSettings.photoProofEnabled,
            onChanged: (v) => setState(() => AppSettings.photoProofEnabled = v),
          ),
          ListTile(
            enabled: AppSettings.photoProofEnabled,
            leading: const Icon(Icons.casino_outlined),
            title: const Text('Photo frequency'),
            subtitle: Text(
                '${AppSettings.photoProofCount} photo(s) in every ${AppSettings.photoProofEvery} check-ins, '
                'at random'),
            onTap: _editPhotoRatio,
          ),
          SwitchListTile(
            secondary: const Icon(Icons.send_to_mobile_outlined),
            title: const Text('Send proof photos to owners immediately'),
            subtitle: const Text(
                'Photos are also included in the monthly PDF report'),
            value: AppSettings.sendProofPhotos,
            onChanged: AppSettings.photoProofEnabled
                ? (v) => setState(() => AppSettings.sendProofPhotos = v)
                : null,
          ),
          _header('Storage'),
          ListTile(
            leading: const Icon(Icons.auto_delete_outlined),
            title: const Text('Auto-delete old data'),
            subtitle: Text(_retentionLabel(AppSettings.retentionMonths)),
            onTap: _editRetention,
          ),
          ListTile(
            leading: const Icon(Icons.cleaning_services_outlined),
            title: const Text('Clean up now'),
            subtitle: Text('Photos & incident media use ${_photoSize ?? '…'}'),
            enabled: AppSettings.retentionMonths > 0,
            onTap: _cleanNow,
          ),
          ListTile(
            leading: const Icon(Icons.delete_forever, color: AppColors.danger),
            title: const Text('Clear all log data',
                style: TextStyle(color: AppColors.danger)),
            subtitle: const Text(
                'Permanently delete every check-in record, incident, photo, video and voice note. '
                'Checkpoints, guards, owners and settings are kept.'),
            onTap: _clearAll,
          ),
          _header('Support contact'),
          ListTile(
            leading: const Icon(Icons.support_agent),
            title: const Text('Shown at the bottom of the Guard Login page'),
            subtitle: Text(AppSettings.supportContact.trim().isEmpty
                ? 'Hidden (empty)'
                : AppSettings.supportContact.trim()),
            isThreeLine: AppSettings.supportContact.contains('\n'),
            onTap: _editSupport,
          ),
          _header('Security'),
          ListTile(
            leading: const Icon(Icons.lock_reset),
            title: const Text('Reset Settings PIN'),
            subtitle: const Text(
                'Set the level-1 Settings PIN back to 1234 (if the owner forgets it)'),
            onTap: _resetSettingsPin,
          ),
          ListTile(
            leading: const Icon(Icons.lock_outline),
            title: const Text('Change developer PIN'),
            subtitle: AppSettings.adminPin == '1234'
                ? const Text(
                    'Still using the default PIN 1234 — please change it',
                    style: TextStyle(color: AppColors.danger))
                : null,
            onTap: _changePin,
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

/// Edits "M photos in every N check-ins".
class _PhotoRatioDialog extends StatefulWidget {
  const _PhotoRatioDialog();

  @override
  State<_PhotoRatioDialog> createState() => _PhotoRatioDialogState();
}

class _PhotoRatioDialogState extends State<_PhotoRatioDialog> {
  final _count = TextEditingController(text: '${AppSettings.photoProofCount}');
  final _every = TextEditingController(text: '${AppSettings.photoProofEvery}');
  String? _error;

  void _submit() {
    final count = int.tryParse(_count.text) ?? 0;
    final every = int.tryParse(_every.text) ?? 0;
    if (every < 1 || every > 100) {
      setState(() => _error = 'Check-ins must be 1–100');
    } else if (count < 1 || count > every) {
      setState(() => _error = 'Photos must be 1–$every');
    } else {
      Navigator.pop(context, (count, every));
    }
  }

  Widget _num(TextEditingController c, String label) => SizedBox(
        width: 72,
        child: TextField(
          controller: c,
          keyboardType: TextInputType.number,
          textAlign: TextAlign.center,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: InputDecoration(labelText: label),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Photo frequency'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _num(_count, 'Photos'),
              const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12),
                  child: Text('in every')),
              _num(_every, 'Check-ins'),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
              'Which check-ins need a photo is chosen at random in each round, '
              'so guards cannot predict it.',
              style: TextStyle(fontSize: 12)),
          if (_error != null)
            Text(_error!, style: const TextStyle(color: AppColors.danger)),
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        FilledButton(onPressed: _submit, child: const Text('Save')),
      ],
    );
  }
}
