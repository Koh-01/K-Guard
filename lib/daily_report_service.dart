import 'package:intl/intl.dart';

import 'db.dart';
import 'incident_categories.dart';
import 'models.dart';
import 'outbox_service.dart';
import 'settings.dart';

/// Daily patrol report, sent to owners who switched on "Daily report".
class DailyReportService {
  static bool _running = false;
  static final _dayKey = DateFormat('yyyy-MM-dd');

  /// Today's report time (e.g. today 08:00).
  static DateTime reportTimeOn(DateTime day) =>
      DateTime(day.year, day.month, day.day)
          .add(Duration(minutes: AppSettings.dailyReportMinute));

  /// The most recent report time that has already passed.
  static DateTime lastDue([DateTime? now]) {
    final n = now ?? DateTime.now();
    final today = reportTimeOn(n);
    return n.isBefore(today)
        ? reportTimeOn(n.subtract(const Duration(days: 1)))
        : today;
  }

  /// Report text for the 24 hours ending at [to].
  static String build({
    required DateTime from,
    required DateTime to,
    required List<Checkpoint> checkpoints,
    required List<CheckinLog> logs,
    required List<Incident> incidents,
    required List<RejectedCheckin> rejected,
  }) {
    final fmt = DateFormat('d MMM HH:mm');
    final perCheckpoint = {for (final c in checkpoints) c.tagId: 0};
    final perGuard = <String, int>{};
    for (final l in logs) {
      if (l.known && perCheckpoint.containsKey(l.tagId)) {
        perCheckpoint[l.tagId] = perCheckpoint[l.tagId]! + 1;
      }
      perGuard[l.guardName] = (perGuard[l.guardName] ?? 0) + 1;
    }
    final missed = [
      for (final c in checkpoints)
        if (perCheckpoint[c.tagId] == 0) c.name
    ];
    final photoRequired = logs.where((l) => l.photoRequired).length;
    final photoMissing = logs.where((l) => l.photoMissing).length;
    final gpsFlagged = logs.where((l) => l.gpsProblem).length;

    final sb = StringBuffer()
      ..writeln('📅 ${AppSettings.siteName} — Daily Patrol Report')
      ..writeln('${fmt.format(from)} → ${fmt.format(to)}')
      ..writeln()
      ..writeln('✅ Check-ins: ${logs.length}');
    if (checkpoints.isNotEmpty) {
      for (final c in checkpoints) {
        sb.writeln('• ${c.name}: ${perCheckpoint[c.tagId]}');
      }
    }
    if (missed.isNotEmpty) sb.writeln('⚠️ Not patrolled: ${missed.join(', ')}');
    if (perGuard.isNotEmpty) {
      sb.writeln(
          '👮 ${perGuard.entries.map((e) => '${e.key} ${e.value}').join(' · ')}');
    }
    if (photoRequired > 0) {
      sb.writeln(
          '📷 Photo proofs: ${photoRequired - photoMissing}/$photoRequired'
          '${photoMissing > 0 ? ' (⚠️ $photoMissing missing)' : ''}');
    }
    if (rejected.isNotEmpty || gpsFlagged > 0) {
      sb.writeln('🚫 GPS problems: ${rejected.length + gpsFlagged}');
    }
    if (incidents.isNotEmpty) {
      final perCat = <String, int>{};
      for (final i in incidents) {
        perCat[i.category] = (perCat[i.category] ?? 0) + 1;
      }
      sb.writeln('🚨 Incidents: ${incidents.length} '
          '(${perCat.entries.map((e) => '${categoryById(e.key).label} ${e.value}').join(', ')})');
    }
    if (logs.isEmpty) sb.writeln('\n⚠️ No check-ins in the last 24 hours.');
    return sb.toString().trim();
  }

  /// Sends the daily report to owners who want it and haven't had today's yet.
  /// Called often (every minute while the app is open); cheap when nothing is due.
  static Future<void> maybeSend() async {
    if (_running || !AppSettings.telegramConfigured) return;
    final due = lastDue();
    final dueKey = _dayKey.format(due);
    final sent = AppSettings.dailyReportSent;
    final recipients = [
      for (final o in AppSettings.owners)
        if (o.dailyReport && (sent[o.chatId] ?? '').compareTo(dueKey) < 0) o
    ];
    if (recipients.isEmpty) return;

    _running = true;
    try {
      final from = due.subtract(const Duration(days: 1));
      final text = build(
        from: from,
        to: due,
        checkpoints: await AppDb.instance.checkpoints(),
        logs: await AppDb.instance.logsBetween(from, due),
        incidents: await AppDb.instance.incidentsBetween(from, due),
        rejected: await AppDb.instance.rejectedBetween(from, due),
      );
      // The outbox delivers it (and retries if offline), so it counts as sent once queued.
      await OutboxService.enqueueText(text,
          targets: [for (final o in recipients) o.chatId]);
      AppSettings.dailyReportSent = {
        ...AppSettings.dailyReportSent,
        for (final o in recipients) o.chatId: dueKey,
      };
    } finally {
      _running = false;
    }
  }

  /// Call when an owner switches the daily report on: start from the next report time
  /// instead of immediately sending the one that is already past.
  static void startFromNext(Owner o) {
    AppSettings.dailyReportSent = {
      ...AppSettings.dailyReportSent,
      o.chatId: _dayKey.format(lastDue()),
    };
  }
}
