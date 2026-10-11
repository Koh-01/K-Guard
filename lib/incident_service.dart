import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

import 'db.dart';
import 'incident_categories.dart';
import 'models.dart';
import 'settings.dart';
import 'telegram_service.dart';
import 'widgets.dart';

/// Sends incident reports to owners, and retries any that didn't reach everyone.
class IncidentService {
  static bool _retrying = false;

  static String message(Incident i) {
    final c = categoryById(i.category);
    final sb = StringBuffer()
      ..writeln('🚨 INCIDENT REPORT — ${AppSettings.siteName}')
      ..writeln()
      ..writeln('${c.emoji} ${c.label}');
    if (i.location != null) sb.writeln('📍 ${i.location}');
    sb
      ..writeln('👮 ${i.guardName}')
      ..writeln('🕒 ${DateFormat('yyyy-MM-dd HH:mm').format(i.time)}');
    if (i.description.isNotEmpty) {
      sb
        ..writeln()
        ..writeln(i.description);
    }
    return sb.toString().trim();
  }

  /// Sends [incidentId] to every owner who hasn't received it yet.
  /// Throws if any owner failed (they will be retried by [retryPending]).
  static Future<void> send(int incidentId) async {
    if (sending.value.contains(incidentId)) return; // already being sent
    sending.value = {...sending.value, incidentId};
    try {
      await _send(incidentId);
    } finally {
      sending.value = {...sending.value}..remove(incidentId);
    }
  }

  /// Incidents currently uploading (the Incidents list shows them as "Sending…").
  static final sending = ValueNotifier<Set<int>>({});

  /// Starts sending without making the guard wait; the result is shown as a snackbar.
  static void sendInBackground(int incidentId) {
    send(incidentId).then((_) {
      showGlobalToast('✅ Incident report sent to all owners');
    }).catchError((Object e) {
      showGlobalToast(
          '⚠️ Incident saved but not sent yet — will retry automatically');
    });
  }

  static Future<void> _send(int incidentId) async {
    final incident = await AppDb.instance.incident(incidentId);
    if (incident == null) return;
    final pending =
        recipients().where((o) => !incident.sentTo.contains(o.chatId)).toList();
    if (pending.isEmpty) return;

    final text = message(incident);
    final shortCaption =
        '🚨 ${categoryById(incident.category).label} · ${incident.guardName}';
    final sentTo = [...incident.sentTo];
    await TelegramService.toOwners((o) async {
      await TelegramService.sendMessageTo(o.chatId, text);
      if (incident.videoPath != null) {
        await TelegramService.sendVideoTo(o.chatId, incident.videoPath!,
            caption: shortCaption);
      }
      for (final p in incident.photoPaths) {
        await TelegramService.sendPhotoTo(o.chatId, p, caption: shortCaption);
      }
      if (incident.voicePath != null) {
        await TelegramService.sendVoiceTo(o.chatId, incident.voicePath!,
            caption: '🎙 Voice note · $shortCaption');
      }
      sentTo.add(o.chatId);
      await AppDb.instance.setIncidentSentTo(incidentId, sentTo);
    }, owners: pending);
  }

  /// Retries incidents from the last 7 days that didn't reach every owner (e.g. no network).
  static Future<void> retryPending() async {
    if (_retrying || !AppSettings.telegramConfigured) return;
    _retrying = true;
    try {
      final recent = await AppDb.instance
          .incidentsSince(DateTime.now().subtract(const Duration(days: 7)));
      for (final i in recent) {
        if (fullySent(i)) continue;
        try {
          await send(i.id!);
        } catch (_) {}
      }
    } finally {
      _retrying = false;
    }
  }

  /// Owners who have "Incident reports" switched on.
  static List<Owner> recipients() =>
      AppSettings.owners.where((o) => o.incidentReports).toList();

  static bool fullySent(Incident i) =>
      recipients().every((o) => i.sentTo.contains(o.chatId));
}
