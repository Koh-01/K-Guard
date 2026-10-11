import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:intl/intl.dart';

import 'db.dart';
import 'incident_categories.dart';
import 'location_service.dart';
import 'models.dart';
import 'pdf_report.dart';
import 'settings.dart';
import 'telegram_service.dart';

class ReportService {
  static final _monthFmt = DateFormat('yyyy-MM');
  static final _dateFmt = DateFormat('yyyy-MM-dd');
  static final _timeFmt = DateFormat('HH:mm:ss');
  static bool _autoRunning = false;

  static String monthKey(int year, int month) =>
      _monthFmt.format(DateTime(year, month));

  static const csvHeader = 'Type,Date,Time,Checkpoint / Location,Guard,Status,'
      'Photo proof,GPS,Distance (m),Map,Details,Tag ID';

  /// One CSV for the month: check-ins, rejected (GPS) check-ins and incidents in a single
  /// table, oldest first. The "Type" column tells them apart (filter it in Excel).
  /// Starts with a UTF-8 BOM so Excel shows Chinese text correctly.
  static List<int> buildCsv(List<CheckinLog> logs,
      {List<Incident> incidents = const [],
      List<RejectedCheckin> rejected = const []}) {
    String esc(String s) => '"${s.replaceAll('"', '""')}"';
    // Quoted: the link itself contains a comma.
    String map(double? lat, double? lng) => lat == null
        ? ''
        : esc(
            'https://maps.google.com/?q=${lat.toStringAsFixed(6)},${lng!.toStringAsFixed(6)}');

    final rows = <(DateTime, List<Object>)>[
      for (final l in logs)
        (
          l.time,
          [
            'Check-in',
            _dateFmt.format(l.time),
            _timeFmt.format(l.time),
            esc(l.checkpointName),
            esc(l.guardName),
            l.known ? 'OK' : 'Unregistered tag',
            !l.photoRequired
                ? ''
                : l.photoPath != null
                    ? 'Taken'
                    : 'MISSING',
            LocationService.label(l.gpsStatus, null),
            l.distanceM?.round() ?? '',
            map(l.lat, l.lng),
            '',
            l.tagId,
          ]
        ),
      for (final r in rejected)
        (
          r.time,
          [
            'Rejected (GPS)',
            _dateFmt.format(r.time),
            _timeFmt.format(r.time),
            esc(r.checkpointName),
            esc(r.guardName),
            LocationService.rejectReason(r.reason, null),
            '',
            LocationService.label(r.reason, null),
            r.distanceM?.round() ?? '',
            map(r.lat, r.lng),
            'Check-in refused: phone was not at the checkpoint',
            r.tagId,
          ]
        ),
      for (final i in incidents)
        (
          i.time,
          [
            'Incident',
            _dateFmt.format(i.time),
            _timeFmt.format(i.time),
            esc(i.location ?? ''),
            esc(i.guardName),
            esc(categoryById(i.category).label),
            '',
            '',
            '',
            '',
            esc([
              if (i.description.isNotEmpty) i.description,
              'Evidence: ${[
                if (i.videoPath != null) 'video',
                if (i.photoPaths.isNotEmpty) '${i.photoPaths.length} photo(s)',
                if (i.voicePath != null) 'voice note',
              ].join(' + ')}',
            ].join(' | ')),
            '',
          ]
        ),
    ]..sort((a, b) => a.$1.compareTo(b.$1));

    final sb = StringBuffer('$csvHeader\n');
    for (final r in rows) {
      sb.writeln(r.$2.join(','));
    }
    return [0xEF, 0xBB, 0xBF, ...utf8.encode(sb.toString())];
  }

  static Future<String> buildSummary(int year, int month, List<CheckinLog> logs,
      {required String sentBy,
      List<Incident> incidents = const [],
      List<RejectedCheckin> rejected = const []}) async {
    final checkpoints = await AppDb.instance.checkpoints();
    final perCheckpoint = <String, int>{for (final c in checkpoints) c.name: 0};
    final perGuard = <String, int>{};
    var unknown = 0;
    for (final l in logs) {
      if (l.known) {
        perCheckpoint[l.checkpointName] =
            (perCheckpoint[l.checkpointName] ?? 0) + 1;
      } else {
        unknown++;
      }
      perGuard[l.guardName] = (perGuard[l.guardName] ?? 0) + 1;
    }
    final missed = perCheckpoint.entries
        .where((e) => e.value == 0)
        .map((e) => e.key)
        .toList();

    final sb = StringBuffer()
      ..writeln('📋 ${AppSettings.siteName} Patrol Report')
      ..writeln('Month: ${monthKey(year, month)}')
      ..writeln('Total check-ins: ${logs.length}')
      ..writeln();
    if (perCheckpoint.isNotEmpty) {
      sb.writeln('📍 Check-ins per checkpoint:');
      for (final e in perCheckpoint.entries) {
        sb.writeln('• ${e.key}: ${e.value}');
      }
      sb.writeln();
    }
    if (perGuard.isNotEmpty) {
      sb.writeln('👮 Check-ins per guard:');
      for (final e in perGuard.entries) {
        sb.writeln('• ${e.key}: ${e.value}');
      }
      sb.writeln();
    }
    if (missed.isNotEmpty) {
      sb.writeln('⚠️ Not patrolled this month: ${missed.join(', ')}');
    }
    if (unknown > 0) sb.writeln('⚠️ Unregistered tag scans: $unknown');
    final gpsProblems = logs.where((l) => l.gpsProblem).length;
    if (gpsProblems > 0) {
      sb.writeln('⚠️ Check-ins away from the checkpoint (GPS): $gpsProblems');
    }

    final required = logs.where((l) => l.photoRequired).toList();
    if (required.isNotEmpty) {
      final missing =
          required.where((l) => l.photoMissing).toList().reversed.toList();
      sb
        ..writeln()
        ..writeln(
            '📷 Photo proofs: ${required.length - missing.length} taken of ${required.length} required');
      if (missing.isNotEmpty) {
        sb.writeln('⚠️ Missing photo proofs: ${missing.length}');
        for (final l in missing.take(15)) {
          sb.writeln(
              '• ${DateFormat('MM-dd HH:mm').format(l.time)} ${l.checkpointName} (${l.guardName})');
        }
        if (missing.length > 15) sb.writeln('• … see CSV for the rest');
      }
    }
    if (rejected.isNotEmpty) {
      sb
        ..writeln()
        ..writeln('🚫 Rejected check-ins (GPS): ${rejected.length}');
      for (final r in rejected.reversed.take(10)) {
        sb.writeln(
            '• ${DateFormat('MM-dd HH:mm').format(r.time)} ${r.checkpointName} '
            '(${r.guardName}) — ${LocationService.rejectReason(r.reason, r.distanceM)}');
      }
      if (rejected.length > 10) sb.writeln('• … see the PDF for the rest');
    }
    if (incidents.isNotEmpty) {
      final perCat = <String, int>{};
      for (final i in incidents) {
        perCat[i.category] = (perCat[i.category] ?? 0) + 1;
      }
      sb
        ..writeln()
        ..writeln('🚨 Incidents reported: ${incidents.length}');
      for (final e in perCat.entries) {
        final c = categoryById(e.key);
        sb.writeln('• ${c.emoji} ${c.label}: ${e.value}');
      }
    }
    sb
      ..writeln()
      ..write(
          '($sentBy — full report with photos in the attached PDF, data in the CSV)');

    var text = sb.toString();
    if (text.length > 4000) text = '${text.substring(0, 3990)}…';
    return text;
  }

  /// Sends a month's report (summary + PDF with photos + CSV) to [owners]
  /// (default: owners with "Monthly report" on).
  /// Calls [onSent] for each owner that received it; throws if any owner failed.
  static Future<void> sendMonthReport(int year, int month,
      {required String sentBy,
      List<Owner>? owners,
      void Function(Owner o)? onSent}) async {
    // Default recipients: owners who have "Monthly report" switched on.
    owners ??= AppSettings.owners.where((o) => o.monthlyReport).toList();
    if (owners.isEmpty) {
      throw TelegramException('No owner has "Monthly report" switched on. '
          'Turn it on for an owner in Settings → Telegram owners.');
    }
    final logs = await AppDb.instance.logsForMonth(year, month);
    final incidents = await AppDb.instance.incidentsForMonth(year, month);
    final rejected = await AppDb.instance.rejectedForMonth(year, month);
    final summary = await buildSummary(year, month, logs,
        sentBy: sentBy, incidents: incidents, rejected: rejected);
    final csv = buildCsv(logs, incidents: incidents, rejected: rejected);
    final key = monthKey(year, month);
    final pdf = await buildPdfReport(PdfReportInput(
      siteName: AppSettings.siteName,
      year: year,
      month: month,
      sentBy: sentBy,
      checkpointNames: [
        for (final c in await AppDb.instance.checkpoints()) c.name
      ],
      logs: logs,
      incidents: incidents,
      rejected: rejected,
      cjkFont: await loadCjkFont(),
    ));
    // Written to a file so it's uploaded once and forwarded to other owners by Telegram file ID.
    final pdfFile = File(
        p.join((await getTemporaryDirectory()).path, 'patrol_report_$key.pdf'));
    await pdfFile.writeAsBytes(pdf, flush: true);
    await TelegramService.toOwners((o) async {
      await TelegramService.sendMessageTo(o.chatId, summary);
      await TelegramService.sendDocumentFileTo(o.chatId, pdfFile.path,
          caption: '${AppSettings.siteName} patrol report $key (with photos)');
      await TelegramService.sendDocumentTo(o.chatId, csv, 'patrol_log_$key.csv',
          caption: '${AppSettings.siteName} patrol log $key '
              '(check-ins, rejected check-ins and incidents: filter by "Type")');
      onSent?.call(o);
    }, owners: owners);
  }

  /// Automatically sends last month's report to each owner who hasn't received it yet.
  /// Called on app start, on resume and hourly; owners that failed (e.g. no network) are retried next time,
  /// and owners that already received it are not sent it again.
  static Future<void> maybeSendMonthlyReport() async {
    if (_autoRunning ||
        !AppSettings.autoMonthlyReport ||
        !AppSettings.telegramConfigured) {
      return;
    }
    final now = DateTime.now();
    final prev = DateTime(now.year, now.month - 1);
    final prevKey = monthKey(prev.year, prev.month);

    final sent = AppSettings.autoReportSent;
    final due = <Owner>[];
    var changed = false;
    final legacy = AppSettings.legacyLastAutoReportMonth;
    for (final o in AppSettings.owners.where((o) => o.monthlyReport)) {
      if (!sent.containsKey(o.chatId)) {
        // Owners from the old single-owner version keep its last-sent month (migrated once);
        // newly added owners start from next month — no back-filling older months.
        sent[o.chatId] = legacy ?? prevKey;
        changed = true;
      }
      if (sent[o.chatId]!.compareTo(prevKey) < 0) due.add(o);
    }
    if (changed) AppSettings.autoReportSent = sent;
    if (legacy != null) AppSettings.clearLegacyLastAutoReportMonth();
    if (due.isEmpty) return;

    _autoRunning = true;
    try {
      await sendMonthReport(prev.year, prev.month,
          sentBy: 'Monthly auto report', owners: due, onSent: (o) {
        AppSettings.autoReportSent = AppSettings.autoReportSent
          ..[o.chatId] = prevKey;
      });
    } catch (_) {
      // Failed owners are retried next time.
    } finally {
      _autoRunning = false;
    }
  }
}
