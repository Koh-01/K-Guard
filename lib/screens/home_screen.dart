import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;

import '../app_theme.dart';
import '../app_ui.dart';
import '../cleanup_service.dart';
import '../db.dart';
import '../location_service.dart';
import '../models.dart';
import '../outbox_service.dart';
import '../patrol_rules.dart';
import '../reminder_service.dart';
import '../settings.dart';
import '../widgets.dart';
import 'camera_screen.dart';
import 'incidents_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _timeFmt = DateFormat('HH:mm');
  final _fullFmt = DateFormat('yyyy-MM-dd HH:mm:ss');
  List<Checkpoint> _checkpoints = [];
  List<CheckinLog> _today = [];

  /// Check-ins in the current patrol cycle (or today, when no patrol schedule is set).
  List<CheckinLog> _cycle = [];
  DateTime? _cycleStart;

  /// "Today", "since 07:00" or "14:00 – 16:00", depending on the progress reset period.
  String get _cycleLabel {
    final start = _cycleStart;
    if (start == null) return '';
    if (AppSettings.patrolIntervalMinutes >= 1440) {
      return AppSettings.patrolStartMinute == 0
          ? 'Today'
          : 'since ${_timeFmt.format(start)}';
    }
    return '${_timeFmt.format(start)} – ${_timeFmt.format(ReminderService.cycleEnd())}';
  }

  bool _scanning = false;
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _load();
    // Roll the progress over when a new patrol cycle starts while the app is open.
    _tick = Timer.periodic(const Duration(minutes: 1), (_) {
      if (ReminderService.cycleStart() != _cycleStart) _load();
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final cps = await AppDb.instance.checkpoints();
    final today = await AppDb.instance.logsForDay(DateTime.now());
    final start = ReminderService.cycleStart();
    final cycle =
        await AppDb.instance.logsBetween(start, ReminderService.cycleEnd());
    if (!mounted) return;
    setState(() {
      _checkpoints = cps;
      _today = today;
      _cycle = cycle;
      _cycleStart = start;
    });
  }

  Future<void> _checkIn() async {
    final guard = AppSettings.currentGuard;
    if (guard == null || _scanning) return;
    setState(() => _scanning = true);
    try {
      // GPS: ask permission first, then read the position while the guard scans the tag.
      final gpsMode = AppSettings.gpsMode;
      Future<GpsResult>? gpsFuture;
      if (gpsMode != 'off') {
        final problem = await LocationService.ensurePermission();
        if (problem != null && gpsMode == 'block') {
          if (mounted) {
            await showMessage(context, 'Location needed', problem,
                icon: const Icon(Icons.location_off,
                    color: AppColors.warning, size: 56));
          }
          return;
        }
        if (problem == null) gpsFuture = LocationService.current();
      }
      if (!mounted) return;

      final tagId = await scanTagWithUi(context,
          prompt: 'Hold the phone near the checkpoint NFC tag');
      if (tagId == null || !mounted) return;

      final now = DateTime.now();
      final cp = await AppDb.instance.checkpointByTag(tagId);

      if (cp != null) {
        // Rule 1: cooldown — the same guard can't check in at the same checkpoint again too soon.
        final last = await AppDb.instance.lastLogForTagByGuard(tagId, guard);
        final cooldown = Duration(minutes: AppSettings.cooldownMinutes);
        if (last != null && now.difference(last.time) < cooldown) {
          if (mounted) {
            await showMessage(
                context,
                'Already checked in',
                'You checked in at "${cp.name}" at ${_timeFmt.format(last.time)}.\n'
                    'Next check-in here is allowed after ${_timeFmt.format(last.time.add(cooldown))}.',
                icon: const Icon(Icons.timer_outlined,
                    color: AppColors.warning, size: 56));
          }
          return;
        }

        // Rule 2: patrol order — only the next checkpoint in the round is accepted.
        final next = PatrolRules.nextFor(guard, _checkpoints);
        if (next != null && next.id != cp.id) {
          if (mounted) await _wrongOrder(guard, cp, next);
          return;
        }
      }

      // Rule 3: GPS — the phone must be at the checkpoint's recorded position.
      GpsFix? fix;
      GpsCheck? gps;
      if (cp != null && gpsMode != 'off') {
        final r = gpsFuture == null ? null : await _waitForGps(gpsFuture);
        fix = r?.fix;
        gps = LocationService.evaluate(fix, cp, AppSettings.gpsRadiusM);
        if ((gps.status == 'far' || gps.status == 'mock') &&
            AppSettings.gpsAlertOwners) {
          _alertOwnersGps(guard, cp, gps, fix!, now);
        }
        if (gpsMode == 'block' && gps.failed) {
          // Not a check-in, but kept so it shows up in the monthly report.
          await AppDb.instance.addRejected(RejectedCheckin(
            time: now,
            guardName: guard,
            tagId: tagId,
            checkpointName: cp.name,
            reason: gps.status,
            distanceM: gps.distanceM,
            lat: fix?.lat,
            lng: fix?.lng,
          ));
          if (mounted) await _gpsRejected(cp, gps, r?.error);
          return;
        }
      }

      // The draw happens and the log is saved *before* the camera opens, so a guard can't
      // dodge the photo by cancelling or killing the app and re-scanning.
      final needPhoto = cp != null && AppSettings.drawPhotoRequired();
      final log = CheckinLog(
        tagId: tagId,
        checkpointName: cp?.name ?? 'Unregistered tag',
        guardName: guard,
        time: now,
        known: cp != null,
        photoRequired: needPhoto,
        lat: fix?.lat,
        lng: fix?.lng,
        distanceM: gps?.distanceM,
        gpsStatus: gps?.status,
      );
      final logId = await AppDb.instance.addLog(log);
      final roundDone = cp != null &&
          AppSettings.enforceOrder &&
          PatrolRules.isLast(cp, _checkpoints);
      if (cp != null && AppSettings.enforceOrder) {
        PatrolRules.complete(guard, cp);
      }
      await _load();

      String? photoPath;
      if (needPhoto && mounted) {
        photoPath = await _takeProofPhoto(logId, log);
        await _load();
      }

      // Only owners who switched on "check-in alerts" get a message per check-in.
      final alertTargets = [
        for (final o in AppSettings.owners)
          if (o.notifyCheckins) o.chatId
      ];
      if (alertTargets.isNotEmpty && AppSettings.telegramConfigured) {
        final photoNote = !needPhoto
            ? ''
            : photoPath != null
                ? '\n📷 Photo proof taken'
                : '\n⚠️ Photo proof MISSING';
        // Queued: delivered as soon as possible and retried if the phone is offline.
        OutboxService.enqueueText(
          '✅ ${AppSettings.siteName}\n${log.guardName} patrolled "${log.checkpointName}"\n'
          '${_fullFmt.format(now)}$photoNote'
          '${fix != null ? '\n📍 GPS ${LocationService.label(gps?.status, gps?.distanceM)} · ${fix.mapsLink}' : ''}',
          targets: alertTargets,
        );
      }

      if (!mounted) return;
      if (cp != null) {
        await showMessage(
            context,
            'Checked in',
            '${cp.name}\n${_fullFmt.format(now)}'
                '${needPhoto && photoPath == null ? '\n\n⚠️ Photo proof skipped — reported as MISSING' : ''}'
                '${gps != null && gps.failed ? '\n\n⚠️ GPS: ${LocationService.label(gps.status, gps.distanceM)}${AppSettings.gpsAlertOwners ? ' — reported to owners' : ''}' : ''}'
                '${roundDone ? '\n\n🏁 Patrol round complete! Next round starts from "${_checkpoints.first.name}".' : ''}',
            icon: Icon(
                needPhoto && photoPath == null
                    ? Icons.warning_amber
                    : Icons.check_circle,
                color: needPhoto && photoPath == null
                    ? AppColors.warning
                    : AppColors.success,
                size: 56));
      } else {
        await showMessage(
            context,
            'Unregistered tag',
            'This tag is not registered as a checkpoint. It was logged as "Unregistered tag".\n'
                'Please contact the admin.\n\nTag ID: $tagId',
            icon: const Icon(Icons.warning_amber,
                color: AppColors.warning, size: 56));
      }
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  /// Waits for the GPS reading, showing a small "checking location" dialog if it isn't ready yet.
  Future<GpsResult> _waitForGps(Future<GpsResult> f) async {
    GpsResult? result;
    f.then((v) => result = v);
    await Future.any(
        [f, Future<void>.delayed(const Duration(milliseconds: 300))]);
    if (result != null || !mounted) return f;

    BuildContext? dialogCtx;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (c) {
        dialogCtx = c;
        return const PopScope(
          canPop: false,
          child: AlertDialog(
            content: Row(children: [
              CircularProgressIndicator(),
              SizedBox(width: 20),
              Expanded(child: Text('Checking your GPS location…')),
            ]),
          ),
        );
      },
    );
    final r = await f;
    if (dialogCtx == null) {
      await WidgetsBinding.instance.endOfFrame; // dialog not built yet
    }
    final dc = dialogCtx;
    if (dc != null && dc.mounted) Navigator.of(dc).pop();
    return r;
  }

  /// Check-in refused because the phone isn't at the checkpoint.
  Future<void> _gpsRejected(Checkpoint cp, GpsCheck gps, String? error) {
    final String title, message;
    final notified =
        AppSettings.gpsAlertOwners ? ' The owners have been notified.' : '';
    switch (gps.status) {
      case 'far':
        title = 'Too far from checkpoint';
        message = 'You are about ${gps.distanceM!.round()} m from "${cp.name}" '
            '(allowed: ${AppSettings.gpsRadiusM} m).\n\n'
            'Check-in NOT recorded.$notified';
      case 'mock':
        title = 'Fake GPS detected';
        message =
            'A fake-location app is being used. Check-in NOT recorded.$notified';
      default:
        title = 'No GPS signal';
        message = '${error ?? 'Could not get an accurate GPS position.'}\n\n'
            'Check-in NOT recorded. Please try again in an open area.';
    }
    return showMessage(context, title, message,
        icon: Icon(
            gps.status == 'none'
                ? Icons.location_searching
                : Icons.wrong_location,
            color: AppColors.danger,
            size: 56));
  }

  /// Tells the owners right away about a check-in from the wrong place (possible cloned tag).
  void _alertOwnersGps(
      String guard, Checkpoint cp, GpsCheck gps, GpsFix fix, DateTime at) {
    final reason = gps.status == 'mock'
        ? 'fake GPS (mock location) app detected'
        : '${gps.distanceM!.round()} m away from the checkpoint (allowed ${AppSettings.gpsRadiusM} m)';
    final action = AppSettings.gpsMode == 'block'
        ? 'REJECTED check-in'
        : 'Suspicious check-in';
    final targets = [
      for (final o in AppSettings.owners)
        if (o.gpsAlerts) o.chatId
    ];
    if (targets.isEmpty) return;
    OutboxService.enqueueText(
        '🚫 ${AppSettings.siteName}\n'
        '$action at "${cp.name}"\n'
        'Guard: $guard\n'
        'Reason: $reason\n'
        '${_fullFmt.format(at)}\n'
        '📍 Where the phone was: ${fix.mapsLink}',
        targets: targets);
  }

  /// Compact progress: one small chip per checkpoint, green = checked in, red = not yet.
  Widget _progressCard(Map<String, DateTime> visited, int done) {
    final total = _checkpoints.length;
    final theme = Theme.of(context);
    final complete = total > 0 && done == total;
    return AppSurface(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Patrol progress', style: theme.textTheme.titleMedium),
                    const SizedBox(height: 2),
                    Text(_cycleLabel, style: theme.textTheme.bodySmall),
                  ],
                ),
              ),
              AppStatusPill(
                label: '$done of $total',
                icon: complete ? Icons.done_all : Icons.route_outlined,
                color:
                    complete ? AppColors.success : theme.colorScheme.secondary,
              ),
            ],
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: total == 0 ? 0 : done / total,
              minHeight: 7,
              color: complete ? AppColors.success : theme.colorScheme.secondary,
              backgroundColor: theme.colorScheme.surfaceContainerHighest,
            ),
          ),
          const SizedBox(height: 14),
          if (total == 0)
            Text(
              'No checkpoints yet. Ask the developer to register checkpoints.',
              style: theme.textTheme.bodySmall,
            )
          else
            Wrap(
              spacing: 7,
              runSpacing: 7,
              children: [
                for (final c in _checkpoints)
                  _checkpointChip(c, visited[c.tagId]),
              ],
            ),
        ],
      ),
    );
  }

  Widget _checkpointChip(Checkpoint c, DateTime? at) {
    final ok = at != null;
    final theme = Theme.of(context);
    final color = ok ? AppColors.success : theme.colorScheme.onSurfaceVariant;
    final label = AppSettings.enforceOrder
        ? '${PatrolRules.positionOf(c, _checkpoints)}. ${c.name}'
        : c.name;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(ok ? Icons.check_circle : Icons.radio_button_unchecked,
              size: 14, color: color),
          const SizedBox(width: 4),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 140),
            child: Text(label,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12)),
          ),
          if (ok) ...[
            const SizedBox(width: 4),
            Text(_timeFmt.format(at),
                style: TextStyle(fontSize: 11, color: color)),
          ],
        ],
      ),
    );
  }

  /// Tells the guard they scanned out of order; offers to report the expected tag as broken.
  Future<void> _wrongOrder(
      String guard, Checkpoint scanned, Checkpoint next) async {
    final pos = PatrolRules.positionOf(next, _checkpoints);
    final report = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        icon: const Icon(Icons.alt_route, color: AppColors.warning, size: 56),
        title: const Text('Wrong patrol order'),
        content: Text('This is "${scanned.name}".\n\n'
            'Your next checkpoint is:\n$pos. ${next.name}\n\n'
            'Please follow the patrol order.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, true),
              child: Text("Can't scan ${next.name}?")),
          FilledButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('OK')),
        ],
      ),
    );
    if (report == true && mounted) await _reportBrokenTag(guard, next);
  }

  /// Opens an "NFC tag not working" incident for [next]; if submitted, the checkpoint is skipped.
  Future<void> _reportBrokenTag(String guard, Checkpoint next) async {
    final submitted =
        await openIncidentForm(context, category: 'nfc', location: next.name);
    if (!submitted) return;
    PatrolRules.complete(guard, next);
    await _load();
    if (mounted) {
      toast(context, '"${next.name}" skipped — NFC problem reported to owners');
    }
  }

  /// Asks for a live camera photo, saves it with the log and (optionally) sends it to owners.
  Future<String?> _takeProofPhoto(int logId, CheckinLog log) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (c) => PopScope(
        canPop: false,
        child: AlertDialog(
          icon: const Icon(Icons.photo_camera, size: 56),
          title: const Text('Photo proof required'),
          content: Text(
              'You were randomly selected to take a photo at "${log.checkpointName}".'),
          actions: [
            FilledButton(
                onPressed: () => Navigator.pop(c),
                child: const Text('Take photo'))
          ],
        ),
      ),
    );
    if (!mounted) return null;
    final shot = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => CameraScreen(
          title: 'Photo proof · ${log.checkpointName}',
          skipWarning:
              'This check-in will be reported to the owners as "Photo MISSING".',
        ),
      ),
    );
    if (shot == null) return null;

    final dir = await CleanupService.photoDir();
    await dir.create(recursive: true);
    final path = p.join(dir.path,
        'log_${logId}_${DateFormat('yyyyMMdd_HHmmss').format(log.time)}.jpg');
    await File(shot).copy(path);
    try {
      await File(shot).delete();
    } catch (_) {}
    await AppDb.instance.setLogPhoto(logId, path);

    if (AppSettings.sendProofPhotos && AppSettings.telegramConfigured) {
      final caption =
          '📷 ${AppSettings.siteName}\n${log.guardName} · ${log.checkpointName}\n${_fullFmt.format(log.time)}';
      final targets = [
        for (final o in AppSettings.owners)
          if (o.proofPhotos) o.chatId
      ];
      if (targets.isNotEmpty) {
        OutboxService.enqueuePhoto(path, caption: caption, targets: targets);
      }
    }
    return path;
  }

  @override
  Widget build(BuildContext context) {
    // Keyed by tag ID (not name) so renaming a checkpoint doesn't lose its check-ins.
    final visitedToday = <String, DateTime>{};
    for (final l in _cycle) {
      if (l.known) {
        visitedToday.putIfAbsent(
            l.tagId, () => l.time); // _cycle is newest first
      }
    }
    final done =
        _checkpoints.where((c) => visitedToday.containsKey(c.tagId)).length;
    final guard = AppSettings.currentGuard;
    final next =
        guard == null ? null : PatrolRules.nextFor(guard, _checkpoints);
    final theme = Theme.of(context);

    return LayoutBuilder(
      builder: (context, constraints) => RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: EdgeInsets.fromLTRB(
              constraints.maxWidth < 400 ? 16 : 20, 20, 20, 32),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      height: 164,
                      child: FilledButton(
                        onPressed: _scanning ? null : _checkIn,
                        style: FilledButton.styleFrom(
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14)),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              width: 58,
                              height: 58,
                              decoration: BoxDecoration(
                                border: Border.all(
                                    color: theme.colorScheme.onPrimary
                                        .withValues(alpha: .35)),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: _scanning
                                  ? Padding(
                                      padding: const EdgeInsets.all(17),
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: theme.colorScheme.onPrimary,
                                      ),
                                    )
                                  : const Icon(Icons.nfc, size: 32),
                            ),
                            const SizedBox(height: 13),
                            Text(
                                _scanning
                                    ? 'Ready for tag…'
                                    : 'Scan checkpoint',
                                style: theme.textTheme.titleLarge?.copyWith(
                                    color: theme.colorScheme.onPrimary)),
                            const SizedBox(height: 3),
                            Text('Hold the back of the phone near the NFC tag',
                                style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onPrimary
                                        .withValues(alpha: .7))),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.danger,
                        side: BorderSide(
                            color: AppColors.danger.withValues(alpha: .5)),
                      ),
                      onPressed: () => openIncidentForm(context),
                      icon: const Icon(Icons.report_problem_outlined),
                      label: const Text('Report incident'),
                    ),
                    if (next != null) ...[
                      const SizedBox(height: 16),
                      AppSurface(
                        color: theme.colorScheme.secondaryContainer,
                        child: ListTile(
                          leading: AppIconBox(Icons.flag_outlined,
                              color: theme.colorScheme.secondary),
                          title: Text('Next · ${next.name}'),
                          subtitle: Text(
                              'Checkpoint ${PatrolRules.positionOf(next, _checkpoints)} of ${_checkpoints.length}'),
                          trailing: TextButton(
                            onPressed: () => _reportBrokenTag(guard!, next),
                            child: const Text("Can't scan?"),
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 24),
                    _progressCard(visitedToday, done),
                    const SizedBox(height: 28),
                    AppSectionHeader("Today's check-ins",
                        caption: '${_today.length} recorded today'),
                    const SizedBox(height: 12),
                    if (_today.isEmpty)
                      const AppSurface(
                        padding: EdgeInsets.all(20),
                        child: Row(
                          children: [
                            AppIconBox(Icons.history_outlined),
                            SizedBox(width: 12),
                            Expanded(child: Text('No check-ins today yet.')),
                          ],
                        ),
                      )
                    else
                      AppSurface(
                        child: Column(
                          children: [
                            for (var index = 0;
                                index < _today.length;
                                index++) ...[
                              if (index > 0)
                                const Divider(indent: 64, endIndent: 16),
                              ListTile(
                                leading: AppIconBox(
                                  _today[index].known
                                      ? Icons.location_on_outlined
                                      : Icons.help_outline,
                                  color: _today[index].known
                                      ? theme.colorScheme.secondary
                                      : AppColors.warning,
                                ),
                                title: Text(_today[index].checkpointName),
                                subtitle: Text(_today[index].guardName),
                                trailing:
                                    Text(_timeFmt.format(_today[index].time)),
                              ),
                            ],
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
