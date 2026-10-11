import 'dart:typed_data';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

import 'settings.dart';

/// Patrol cycles and the alarm that reminds guards to start each patrol.
class ReminderService {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static const _firstId = 1000;
  static const _count =
      48; // alarms scheduled ahead; topped up whenever the app opens
  static bool _initialized = false;

  /// Start of the patrol cycle containing [now].
  static DateTime cycleStart([DateTime? now]) {
    final n = now ?? DateTime.now();
    final interval = AppSettings.patrolIntervalMinutes;
    final anchor = DateTime(n.year, n.month, n.day)
        .add(Duration(minutes: AppSettings.patrolStartMinute));
    final diff = n.difference(anchor).inMinutes;
    final k = (diff / interval).floor(); // negative before today's first cycle
    return anchor.add(Duration(minutes: k * interval));
  }

  static DateTime cycleEnd([DateTime? now]) =>
      cycleStart(now).add(Duration(minutes: AppSettings.patrolIntervalMinutes));

  static Future<void> _init() async {
    if (_initialized) return;
    await _plugin.initialize(
      settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher')),
    );
    _initialized = true;
  }

  static AndroidFlutterLocalNotificationsPlugin? get _android =>
      _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();

  /// Asks for notification / exact-alarm permission where the Android version needs it.
  static Future<void> requestPermissions() async {
    await _init();
    await _android?.requestNotificationsPermission();
    if (await _android?.canScheduleExactNotifications() == false) {
      await _android?.requestExactAlarmsPermission();
    }
  }

  static final _details = NotificationDetails(
    android: AndroidNotificationDetails(
      'patrol_reminder',
      'Patrol reminders',
      channelDescription: 'Alarm at the start of each patrol cycle',
      importance: Importance.max,
      priority: Priority.max,
      category: AndroidNotificationCategory.alarm,
      audioAttributesUsage:
          AudioAttributesUsage.alarm, // alarm volume: rings even in silent mode
      sound: const UriAndroidNotificationSound(
          'content://settings/system/alarm_alert'),
      visibility: NotificationVisibility.public,
      additionalFlags: Int32List.fromList(
          [4]), // FLAG_INSISTENT: keep ringing until the guard taps it
      timeoutAfter: 5 * 60 * 1000, // stop ringing after 5 minutes
    ),
  );

  /// Re-schedules the upcoming patrol alarms (or cancels them when reminders are off).
  static Future<void> reschedule() async {
    await _init();
    for (var i = 0; i < _count; i++) {
      await _plugin.cancel(id: _firstId + i);
    }
    if (!AppSettings.reminderEnabled) return;

    final exact = await _android?.canScheduleExactNotifications() ?? true;
    final mode = exact
        ? AndroidScheduleMode.exactAllowWhileIdle
        : AndroidScheduleMode.inexactAllowWhileIdle;
    final interval = Duration(minutes: AppSettings.patrolIntervalMinutes);
    var at = cycleEnd();
    for (var i = 0; i < _count; i++, at = at.add(interval)) {
      final end = at.add(interval);
      await _plugin.zonedSchedule(
        id: _firstId + i,
        scheduledDate: tz.TZDateTime.from(at, tz.UTC),
        notificationDetails: _details,
        androidScheduleMode: mode,
        title: '🔔 Time to patrol — ${AppSettings.siteName}',
        body:
            'Patrol ${_hm(at)} – ${_hm(end)}: please check in at all checkpoints.',
      );
    }
  }

  static String _hm(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}
