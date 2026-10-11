import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'db.dart';
import 'settings.dart';

/// Deletes old check-in data so the phone doesn't run out of storage.
class CleanupService {
  static Future<Directory> photoDir() async => Directory(
      p.join((await getApplicationDocumentsDirectory()).path, 'proof_photos'));

  static Future<Directory> incidentMediaDir() async => Directory(p.join(
      (await getApplicationDocumentsDirectory()).path, 'incident_media'));

  /// First day of the oldest month that is kept.
  static DateTime cutoff(int months, [DateTime? now]) {
    final n = now ?? DateTime.now();
    return DateTime(n.year, n.month - months);
  }

  /// Deletes logs and photos older than the retention period. Returns the number of logs deleted.
  static Future<int> run({int? months}) async {
    final keep = months ?? AppSettings.retentionMonths;
    if (keep <= 0) return 0;
    final cut = cutoff(keep);
    final paths = [
      ...await AppDb.instance.deleteLogsBefore(cut),
      ...await AppDb.instance.deleteIncidentsBefore(cut),
    ];
    await AppDb.instance.deleteRejectedBefore(cut);
    for (final path in paths) {
      try {
        await File(path).delete();
      } catch (_) {}
    }
    return paths.length;
  }

  /// Deletes ALL check-in logs, incidents, proof photos and incident media. Checkpoints, guards, owners and settings are kept.
  /// Returns the number of logs deleted.
  static Future<int> clearAll() async {
    final n = await AppDb.instance.deleteAllLogs();
    for (final dir in [await photoDir(), await incidentMediaDir()]) {
      if (await dir.exists()) await dir.delete(recursive: true);
    }
    return n;
  }

  /// Total size of stored proof photos and incident media, in bytes.
  static Future<int> photoBytes() async {
    var total = 0;
    for (final dir in [await photoDir(), await incidentMediaDir()]) {
      if (!await dir.exists()) continue;
      await for (final f in dir.list()) {
        if (f is File) total += await f.length();
      }
    }
    return total;
  }

  static String formatBytes(int b) {
    if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(0)} KB';
    if (b < 1024 * 1024 * 1024) {
      return '${(b / 1024 / 1024).toStringAsFixed(1)} MB';
    }
    return '${(b / 1024 / 1024 / 1024).toStringAsFixed(2)} GB';
  }
}
