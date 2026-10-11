import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:nfc_manager/nfc_manager.dart';
import 'package:nfc_manager/nfc_manager_android.dart';
import 'package:nfc_manager/nfc_manager_ios.dart';

class NfcService {
  static Completer<String?>? _pending;

  /// Android: whether K Guard currently holds the NFC reader (see [startGuard]).
  static bool _guardActive = false;

  static Future<NfcAvailability> availability() =>
      NfcManager.instance.checkAvailability();

  /// Android only. Keeps NFC reader mode on for as long as the app is in the foreground,
  /// so every tag touch comes to K Guard. Without this, touching a tag while the app isn't
  /// actively scanning makes Android show its own "choose an app" (Tags / WeChat) popup.
  /// Tags touched while not scanning are simply ignored.
  static Future<void> startGuard() {
    if (!Platform.isAndroid || _guardActive) return Future.value();
    return _starting ??= _startGuard().whenComplete(() => _starting = null);
  }

  static Future<void>? _starting;

  static Future<void> _startGuard() async {
    try {
      if (await availability() != NfcAvailability.enabled) return;
      await NfcManager.instance.startSession(
        pollingOptions: NfcPollingOption.values.toSet(),
        // No system beep: ignored tags must not sound like a successful scan.
        // A real scan gives a vibration instead (see _onDiscovered).
        noPlatformSoundsAndroid: true,
        onDiscovered: _onDiscovered,
      );
      _guardActive = true;
    } catch (_) {}
  }

  /// Android only. Releases the NFC reader (app going to the background).
  static Future<void> stopGuard() async {
    if (!_guardActive) return;
    _guardActive = false;
    try {
      await NfcManager.instance.stopSession();
    } catch (_) {}
  }

  static void _onDiscovered(NfcTag tag) {
    final p = _pending;
    if (p == null || p.isCompleted) return; // not scanning: swallow the tag
    HapticFeedback.mediumImpact();
    p.complete(extractId(tag));
  }

  /// 读取一个 NFC 标签的 UID（例如 "04:A2:3B:1C:55:80:00"）。
  /// 用户取消或出错时返回 null。
  static Future<String?> readTagId(
      {String iosAlert = 'Hold the phone near the checkpoint NFC tag'}) async {
    final prev = _pending;
    if (prev != null && !prev.isCompleted) prev.complete(null);
    final completer = Completer<String?>();
    _pending = completer;

    if (Platform.isAndroid) {
      await startGuard(); // the always-on reader delivers the next tag to [completer]
      if (!_guardActive && !completer.isCompleted) completer.complete(null);
      return completer.future;
    }

    // iOS: one system NFC sheet per scan.
    try {
      await NfcManager.instance.startSession(
        pollingOptions: NfcPollingOption.values.toSet(),
        alertMessageIos: iosAlert,
        onDiscovered: (NfcTag tag) async {
          final id = extractId(tag);
          if (id == null) {
            await NfcManager.instance
                .stopSession(errorMessageIos: 'Unable to read this tag');
          } else {
            await NfcManager.instance.stopSession(alertMessageIos: 'Tag read');
          }
          if (!completer.isCompleted) completer.complete(id);
        },
        onSessionErrorIos: (_) {
          if (!completer.isCompleted) completer.complete(null);
        },
      );
    } catch (_) {
      if (!completer.isCompleted) completer.complete(null);
    }
    return completer.future;
  }

  /// 取消正在进行的扫描
  static Future<void> cancel() async {
    if (Platform.isIOS) {
      try {
        await NfcManager.instance.stopSession();
      } catch (_) {}
    }
    // Android keeps the reader on (so no system popup); just stop waiting for a tag.
    final p = _pending;
    if (p != null && !p.isCompleted) p.complete(null);
  }

  /// 取出标签 UID（Android 通用；iOS 支持 MiFare / ISO7816 / ISO15693 / FeliCa）
  static String? extractId(NfcTag tag) {
    Uint8List? bytes;
    if (Platform.isAndroid) {
      bytes = NfcTagAndroid.from(tag)?.id;
    } else {
      bytes = MiFareIos.from(tag)?.identifier ??
          Iso7816Ios.from(tag)?.identifier ??
          Iso15693Ios.from(tag)?.identifier ??
          FeliCaIos.from(tag)?.currentIDm;
    }
    if (bytes == null || bytes.isEmpty) return null;
    return bytes
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join(':')
        .toUpperCase();
  }
}
