import 'dart:async';
import 'dart:math' as math;

import 'package:geolocator/geolocator.dart';

import 'models.dart';

/// A GPS reading.
class GpsFix {
  final double lat;
  final double lng;

  /// Estimated error radius in metres.
  final double accuracy;

  /// Position came from a fake-location ("mock location") app.
  final bool mocked;

  const GpsFix(this.lat, this.lng, this.accuracy, {this.mocked = false});

  String get mapsLink =>
      'https://maps.google.com/?q=${lat.toStringAsFixed(6)},${lng.toStringAsFixed(6)}';
}

/// Result of reading the GPS: a fix, or a human-readable reason there isn't one.
class GpsResult {
  final GpsFix? fix;
  final String? error;
  const GpsResult.ok(GpsFix this.fix) : error = null;
  const GpsResult.failed(String this.error) : fix = null;
}

/// Outcome of comparing a check-in position with the checkpoint's recorded position.
class GpsCheck {
  /// 'ok', 'far', 'mock', 'none' (no GPS fix) or 'noref' (checkpoint has no recorded position).
  final String status;
  final double? distanceM;
  const GpsCheck(this.status, [this.distanceM]);

  /// Guard is not (provably) at the checkpoint.
  bool get failed => status == 'far' || status == 'mock' || status == 'none';
}

class LocationService {
  /// Leeway for GPS error: a reading with ±20 m accuracy may be up to 20 m off, so the guard
  /// gets that much benefit of the doubt — capped, so a very poor reading can't excuse anything.
  static const maxLeewayM = 25.0;

  /// Readings worse than this are treated as "no GPS" (not trustworthy enough to judge).
  static const maxUsableAccuracyM = 100.0;

  /// Makes sure location is on and permitted. Returns an error message, or null if OK.
  static Future<String?> ensurePermission() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      return 'Location (GPS) is turned off. Please turn it on in the phone settings.';
    }
    var p = await Geolocator.checkPermission();
    if (p == LocationPermission.denied) {
      p = await Geolocator.requestPermission();
    }
    if (p == LocationPermission.denied ||
        p == LocationPermission.deniedForever) {
      return 'K Guard needs location permission to verify check-ins. '
          'Please allow "Location" for K Guard in the phone settings.';
    }
    return null;
  }

  /// Reads the current position (high accuracy, up to [timeout]).
  static Future<GpsResult> current(
      {Duration timeout = const Duration(seconds: 20)}) async {
    final problem = await ensurePermission();
    if (problem != null) return GpsResult.failed(problem);
    try {
      final p = await Geolocator.getCurrentPosition(
        locationSettings: LocationSettings(
            accuracy: LocationAccuracy.high, timeLimit: timeout),
      );
      return GpsResult.ok(
          GpsFix(p.latitude, p.longitude, p.accuracy, mocked: p.isMocked));
    } on TimeoutException {
      return const GpsResult.failed(
          'Could not get a GPS position. Please stand in the open and try again.');
    } catch (e) {
      return GpsResult.failed('GPS error: $e');
    }
  }

  /// Great-circle distance in metres.
  static double distance(double lat1, double lng1, double lat2, double lng2) {
    const r = 6371000.0;
    double rad(double d) => d * math.pi / 180;
    final dLat = rad(lat2 - lat1), dLng = rad(lng2 - lng1);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(rad(lat1)) *
            math.cos(rad(lat2)) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    return 2 * r * math.asin(math.min(1, math.sqrt(a)));
  }

  /// Compares [fix] with [cp]'s recorded position.
  static GpsCheck evaluate(GpsFix? fix, Checkpoint cp, int radiusM) {
    if (!cp.hasLocation) return const GpsCheck('noref');
    if (fix == null || fix.accuracy > maxUsableAccuracyM) {
      return const GpsCheck('none');
    }
    final d = distance(fix.lat, fix.lng, cp.lat!, cp.lng!);
    if (fix.mocked) return GpsCheck('mock', d);
    final leeway = math.min(fix.accuracy, maxLeewayM);
    return GpsCheck(d - leeway > radiusM ? 'far' : 'ok', d);
  }

  /// Short label for reports.
  static String label(String? status, double? distanceM) {
    final m = distanceM == null ? '' : ' ${distanceM.round()} m';
    switch (status) {
      case 'ok':
        return 'OK$m';
      case 'far':
        return 'TOO FAR$m';
      case 'mock':
        return 'FAKE GPS';
      case 'none':
        return 'No GPS';
      case 'noref':
        return 'Not set';
      default:
        return '';
    }
  }

  /// Why a check-in was rejected, for reports.
  static String rejectReason(String reason, double? distanceM) {
    switch (reason) {
      case 'far':
        return 'Too far${distanceM == null ? '' : ' (${distanceM.round()} m)'}';
      case 'mock':
        return 'Fake GPS app';
      default:
        return 'No GPS signal';
    }
  }
}
