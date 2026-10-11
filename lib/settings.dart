import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart' show ThemeMode, ValueNotifier;
import 'package:shared_preferences/shared_preferences.dart';

/// A guard account on this phone.
class Guard {
  final String name;
  final String pin;

  const Guard(this.name, this.pin);

  Map<String, String> toJson() => {'name': name, 'pin': pin};

  factory Guard.fromJson(Map<String, dynamic> j) =>
      Guard(j['name'] as String, j['pin'] as String);
}

/// A report recipient (Telegram chat).
class Owner {
  final String chatId;
  final String name;

  /// Receives a Telegram message on every check-in.
  final bool notifyCheckins;

  /// Receives the daily patrol report.
  final bool dailyReport;

  /// Receives the monthly report (summary + PDF + CSV).
  final bool monthlyReport;

  /// Receives instant alerts when a check-in fails the GPS check.
  final bool gpsAlerts;

  /// Receives incident reports (with their photos / video / voice notes).
  final bool incidentReports;

  /// Receives proof photos as soon as guards take them.
  final bool proofPhotos;

  const Owner(this.chatId, this.name,
      {this.notifyCheckins = false,
      this.dailyReport = false,
      this.monthlyReport = true,
      this.gpsAlerts = true,
      this.incidentReports = true,
      this.proofPhotos = true});

  Owner copyWith(
          {String? name,
          bool? notifyCheckins,
          bool? dailyReport,
          bool? monthlyReport,
          bool? gpsAlerts,
          bool? incidentReports,
          bool? proofPhotos}) =>
      Owner(
        chatId,
        name ?? this.name,
        notifyCheckins: notifyCheckins ?? this.notifyCheckins,
        dailyReport: dailyReport ?? this.dailyReport,
        monthlyReport: monthlyReport ?? this.monthlyReport,
        gpsAlerts: gpsAlerts ?? this.gpsAlerts,
        incidentReports: incidentReports ?? this.incidentReports,
        proofPhotos: proofPhotos ?? this.proofPhotos,
      );

  Map<String, Object> toJson() => {
        'chat_id': chatId,
        'name': name,
        'notify_checkins': notifyCheckins,
        'daily_report': dailyReport,
        'monthly_report': monthlyReport,
        'gps_alerts': gpsAlerts,
        'incident_reports': incidentReports,
        'proof_photos': proofPhotos,
      };

  /// [legacyNotify]: the old app-wide "notify on every check-in" switch, for owners saved
  /// before notifications were per owner.
  factory Owner.fromJson(Map<String, dynamic> j, {bool legacyNotify = false}) =>
      Owner(
        j['chat_id'] as String,
        j['name'] as String,
        notifyCheckins: j['notify_checkins'] as bool? ?? legacyNotify,
        dailyReport: j['daily_report'] as bool? ?? false,
        monthlyReport:
            j['monthly_report'] as bool? ?? true, // everyone got it before
        // Everyone received these before they became per-owner options.
        gpsAlerts: j['gps_alerts'] as bool? ?? true,
        incidentReports: j['incident_reports'] as bool? ?? true,
        proofPhotos: j['proof_photos'] as bool? ?? true,
      );
}

/// App settings (stored on this device).
class AppSettings {
  static const maxGuards = 6;

  static late SharedPreferences _p;

  static Future<void> init() async {
    _p = await SharedPreferences.getInstance();
    themeMode.value =
        ThemeMode.values.byName(_p.getString('theme_mode') ?? 'system');
  }

  /// App theme (system / light / dark). Listen to this to rebuild the app when it changes.
  static final themeMode = ValueNotifier<ThemeMode>(ThemeMode.system);

  static void setThemeMode(ThemeMode m) {
    themeMode.value = m;
    _p.setString('theme_mode', m.name);
  }

  static String get siteName => _p.getString('site_name') ?? 'My Property';
  static set siteName(String v) => _p.setString('site_name', v);

  /// Owner-selected community logo shown beside the property name before login.
  static String? get communityLogoPath => _p.getString('community_logo_path');
  static set communityLogoPath(String? v) => v == null
      ? _p.remove('community_logo_path')
      : _p.setString('community_logo_path', v);

  static String get botToken => _p.getString('bot_token') ?? '';
  static set botToken(String v) => _p.setString('bot_token', v.trim());

  static List<Owner> get owners {
    final raw = _p.getString('owners');
    if (raw != null) {
      return (jsonDecode(raw) as List)
          .map((e) => Owner.fromJson(e as Map<String, dynamic>,
              legacyNotify: _legacyInstantNotify))
          .toList();
    }
    // Migrate the old single Chat ID setting.
    final legacy = _p.getString('chat_id') ?? '';
    return legacy.isEmpty
        ? []
        : [Owner(legacy, 'Owner', notifyCheckins: _legacyInstantNotify)];
  }

  static set owners(List<Owner> v) =>
      _p.setString('owners', jsonEncode(v.map((o) => o.toJson()).toList()));

  static bool get telegramConfigured =>
      botToken.isNotEmpty && owners.isNotEmpty;

  /// PIN for the level-1 Settings page (owners / supervisors).
  static const defaultSettingsPin = '1234';
  static String get settingsPin =>
      _p.getString('settings_pin') ?? defaultSettingsPin;
  static set settingsPin(String v) => _p.setString('settings_pin', v);

  /// PIN for the level-2 Developer settings.
  static String get adminPin => _p.getString('admin_pin') ?? '1234';
  static set adminPin(String v) => _p.setString('admin_pin', v);

  // ---------- Guard accounts ----------

  static List<Guard> get guards {
    final raw = _p.getString('guard_accounts');
    if (raw == null) return [];
    return (jsonDecode(raw) as List)
        .map((e) => Guard.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  static set guards(List<Guard> v) => _p.setString(
      'guard_accounts', jsonEncode(v.map((g) => g.toJson()).toList()));

  /// Name of the guard currently logged in, or null.
  static String? get currentGuard {
    final g = _p.getString('current_guard');
    return g != null && guards.any((x) => x.name == g) ? g : null;
  }

  static set currentGuard(String? v) =>
      v == null ? _p.remove('current_guard') : _p.setString('current_guard', v);

  // ---------- Photo proof ----------

  /// Randomly require a camera photo on some check-ins.
  static bool get photoProofEnabled =>
      _p.getBool('photo_proof_enabled') ?? false;
  static set photoProofEnabled(bool v) => _p.setBool('photo_proof_enabled', v);

  /// Out of every [photoProofEvery] check-ins, [photoProofCount] randomly require a photo.
  static int get photoProofEvery => _p.getInt('photo_proof_every') ?? 5;
  static int get photoProofCount => _p.getInt('photo_proof_count') ?? 1;

  static void setPhotoProofRatio(int count, int every) {
    _p.setInt('photo_proof_count', count);
    _p.setInt('photo_proof_every', every);
    _p.remove('photo_bag'); // start a fresh random round
  }

  /// Send each proof photo to owners as soon as it is taken.
  static bool get sendProofPhotos => _p.getBool('send_proof_photos') ?? true;
  static set sendProofPhotos(bool v) => _p.setBool('send_proof_photos', v);

  /// Returns whether the next check-in needs a photo.
  /// Draws from a shuffled "bag" of [photoProofEvery] slots with [photoProofCount] photo slots,
  /// so exactly M of every N check-ins need a photo, at unpredictable positions.
  static bool drawPhotoRequired() {
    if (!photoProofEnabled) return false;
    var bag = _p.getStringList('photo_bag') ?? [];
    if (bag.isEmpty) {
      final every = photoProofEvery,
          count = photoProofCount.clamp(0, photoProofEvery);
      bag = [for (var i = 0; i < every; i++) i < count ? '1' : '0']
        ..shuffle(Random.secure());
    }
    final next = bag.removeLast();
    _p.setStringList('photo_bag', bag);
    return next == '1';
  }

  // ---------- Support contact (shown on the login page) ----------

  static const defaultSupportContact = 'Need help? Contact KTech Solution';

  /// Shown at the bottom of the Guard Login page. Empty = hidden.
  static String get supportContact {
    final v = _p.getString('support_contact');
    // The old default (company renamed): follow the new default instead.
    if (v == null || v == 'Need help? Contact KTech.prod') {
      return defaultSupportContact;
    }
    return v;
  }

  static set supportContact(String v) => _p.setString('support_contact', v);

  // ---------- GPS location check ----------

  /// 'off', 'flag' (record + mark in reports) or 'block' (refuse the check-in).
  static String get gpsMode => _p.getString('gps_mode') ?? 'block';
  static set gpsMode(String v) => _p.setString('gps_mode', v);

  /// Check-ins further than this from the checkpoint's recorded position fail the GPS check.
  static int get gpsRadiusM => _p.getInt('gps_radius') ?? 50;
  static set gpsRadiusM(int v) => _p.setInt('gps_radius', v);

  /// Send owners an instant Telegram alert when a check-in fails the GPS check.
  /// (Rejected check-ins are always kept for the monthly report either way.)
  static bool get gpsAlertOwners => _p.getBool('gps_alert_owners') ?? true;
  static set gpsAlertOwners(bool v) => _p.setBool('gps_alert_owners', v);

  // ---------- Patrol rules ----------

  /// A guard can't check in at the same checkpoint again within this many minutes.
  static int get cooldownMinutes => _p.getInt('cooldown_minutes') ?? 1;
  static set cooldownMinutes(int v) => _p.setInt('cooldown_minutes', v);

  /// Guards must visit checkpoints in the configured order.
  static bool get enforceOrder => _p.getBool('enforce_order') ?? false;
  static set enforceOrder(bool v) {
    _p.setBool('enforce_order', v);
    resetOrderProgress();
  }

  /// Checkpoint id each guard last completed in the patrol order.
  static int? lastOrderedCheckpoint(String guard) {
    final raw = _p.getString('order_progress');
    return raw == null
        ? null
        : (jsonDecode(raw) as Map<String, dynamic>)[guard] as int?;
  }

  static void setLastOrderedCheckpoint(String guard, int checkpointId) {
    final raw = _p.getString('order_progress');
    final map = raw == null
        ? <String, dynamic>{}
        : jsonDecode(raw) as Map<String, dynamic>;
    map[guard] = checkpointId;
    _p.setString('order_progress', jsonEncode(map));
  }

  /// Every guard starts again from the first checkpoint.
  static void resetOrderProgress() => _p.remove('order_progress');

  // ---------- Patrol schedule / reminders ----------

  /// Ring an alarm at the start of every patrol cycle.
  static bool get reminderEnabled => _p.getBool('reminder_enabled') ?? false;
  static set reminderEnabled(bool v) => _p.setBool('reminder_enabled', v);

  /// Length of one patrol cycle in minutes (a divisor of 24 h, so cycles line up every day).
  /// Progress on the Home screen resets at the start of each cycle. Default: once a day.
  static int get patrolIntervalMinutes => _p.getInt('patrol_interval') ?? 1440;
  static set patrolIntervalMinutes(int v) => _p.setInt('patrol_interval', v);

  /// Time of day the first cycle starts, in minutes after midnight.
  static int get patrolStartMinute => _p.getInt('patrol_start') ?? 0;
  static set patrolStartMinute(int v) => _p.setInt('patrol_start', v);

  // ---------- Data retention ----------

  /// Keep the current month plus this many previous months; older logs and photos are deleted.
  /// 0 = never delete.
  static int get retentionMonths => _p.getInt('retention_months') ?? 0;
  static set retentionMonths(int v) => _p.setInt('retention_months', v);

  // ---------- Reports ----------

  /// Automatically send last month's report after the 1st of each month.
  static bool get autoMonthlyReport => _p.getBool('auto_monthly') ?? true;
  static set autoMonthlyReport(bool v) => _p.setBool('auto_monthly', v);

  /// Notify the owner on every check-in.
  /// Old app-wide switch; now per owner ([Owner.notifyCheckins]). Read only for migration.
  static bool get _legacyInstantNotify => _p.getBool('instant_notify') ?? false;

  // ---------- Daily report ----------

  /// Time of day the daily report is sent (minutes after midnight). It covers the 24 hours
  /// before that time. Default 08:00.
  static int get dailyReportMinute =>
      _p.getInt('daily_report_minute') ?? 8 * 60;
  static set dailyReportMinute(int v) => _p.setInt('daily_report_minute', v);

  /// Last daily report sent to each owner: chat ID -> yyyy-MM-dd.
  static Map<String, String> get dailyReportSent {
    final raw = _p.getString('daily_report_sent');
    return raw == null ? {} : Map<String, String>.from(jsonDecode(raw) as Map);
  }

  static set dailyReportSent(Map<String, String> v) =>
      _p.setString('daily_report_sent', jsonEncode(v));

  // ---------- SOS ----------

  static String get sosName => _p.getString('sos_name') ?? '';
  static set sosName(String v) => _p.setString('sos_name', v.trim());

  static String get sosPhone => _p.getString('sos_phone') ?? '';
  static set sosPhone(String v) => _p.setString('sos_phone', v.trim());

  /// Last month auto-reported to each owner: chat ID -> yyyy-MM.
  static Map<String, String> get autoReportSent {
    final raw = _p.getString('auto_report_sent');
    return raw == null ? {} : Map<String, String>.from(jsonDecode(raw) as Map);
  }

  static set autoReportSent(Map<String, String> v) =>
      _p.setString('auto_report_sent', jsonEncode(v));

  /// Old single-owner value, used only to migrate [autoReportSent].
  static String? get legacyLastAutoReportMonth =>
      _p.getString('last_auto_report_month');

  static void clearLegacyLastAutoReportMonth() =>
      _p.remove('last_auto_report_month');
}
