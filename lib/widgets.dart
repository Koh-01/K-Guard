import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nfc_manager/nfc_manager.dart' show NfcAvailability;

import 'app_theme.dart';
import 'app_ui.dart';
import 'nfc_service.dart';
import 'settings.dart';

/// Checks NFC and scans a tag. Shows a "hold near tag" dialog on Android; iOS uses the system sheet.
Future<String?> scanTagWithUi(BuildContext context,
    {String prompt = 'Hold the back of the phone near the NFC tag'}) async {
  final availability = await NfcService.availability();
  if (availability != NfcAvailability.enabled) {
    if (context.mounted) {
      await showMessage(
        context,
        'NFC unavailable',
        availability == NfcAvailability.disabled
            ? 'NFC is turned off. Please enable NFC in system settings and try again.'
            : 'This device does not support NFC.',
      );
    }
    return null;
  }
  if (!context.mounted) return null;

  BuildContext? dialogCtx;
  if (Platform.isAndroid) {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (c) {
        dialogCtx = c;
        return AlertDialog(
          title: const Text('Ready to scan'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const AppIconBox(Icons.nfc, color: AppColors.blue, size: 72),
              const SizedBox(height: 16),
              Text(prompt, textAlign: TextAlign.center),
            ],
          ),
          actions: const [
            TextButton(onPressed: NfcService.cancel, child: Text('Cancel'))
          ],
        );
      },
    );
  }

  final id = await NfcService.readTagId(iosAlert: prompt);
  final dc = dialogCtx;
  if (dc != null && dc.mounted) Navigator.of(dc).pop();
  return id;
}

Future<void> showMessage(BuildContext context, String title, String message,
    {Widget? icon}) {
  return showDialog<void>(
    context: context,
    builder: (c) => AlertDialog(
      icon: icon,
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: const Text('OK'))
      ],
    ),
  );
}

Future<bool> confirm(BuildContext context, String title, String message) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel')),
        FilledButton(
            onPressed: () => Navigator.pop(c, true), child: const Text('OK')),
      ],
    ),
  );
  return r ?? false;
}

Future<String?> editText(
  BuildContext context,
  String title, {
  String initial = '',
  String? hint,
  bool obscure = false,
  TextInputType? keyboardType,
  bool multiline = false,
}) {
  final ctrl = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: ctrl,
        autofocus: true,
        obscureText: obscure,
        keyboardType: multiline ? TextInputType.multiline : keyboardType,
        minLines: multiline ? 3 : 1,
        maxLines: multiline ? 8 : 1,
        decoration: InputDecoration(hintText: hint),
        onSubmitted: multiline ? null : (v) => Navigator.pop(c, v.trim()),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
        FilledButton(
            onPressed: () => Navigator.pop(c, ctrl.text.trim()),
            child: const Text('OK')),
      ],
    ),
  );
}

/// Asks for a numeric PIN (4–6 digits).
Future<String?> askPin(BuildContext context, String title, {String? hint}) {
  final ctrl = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: ctrl,
        autofocus: true,
        obscureText: true,
        keyboardType: TextInputType.number,
        maxLength: 6,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: InputDecoration(hintText: hint ?? 'PIN'),
        onSubmitted: (v) => Navigator.pop(c, v),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
        FilledButton(
            onPressed: () => Navigator.pop(c, ctrl.text),
            child: const Text('OK')),
      ],
    ),
  );
}

/// Asks for the developer PIN; returns true if correct.
Future<bool> askAdminPin(BuildContext context) async {
  final pin = await askPin(context, 'Developer PIN');
  if (pin == null) return false;
  if (pin == AppSettings.adminPin) return true;
  if (context.mounted) toast(context, 'Wrong PIN');
  return false;
}

/// Asks for the Settings PIN; returns true if correct. The Developer PIN also works,
/// so the developer can always get in (e.g. if the owner forgets the Settings PIN).
Future<bool> askSettingsPin(BuildContext context) async {
  final pin = await askPin(context, 'Settings PIN');
  if (pin == null) return false;
  if (pin == AppSettings.settingsPin || pin == AppSettings.adminPin) {
    return true;
  }
  if (context.mounted) toast(context, 'Wrong PIN');
  return false;
}

void toast(BuildContext context, String msg) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(msg)));
}

/// Lets background work (e.g. incident uploads) show a snackbar on whatever screen is open.
final messengerKey = GlobalKey<ScaffoldMessengerState>();

void showGlobalToast(String msg) {
  messengerKey.currentState
    ?..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(msg)));
}

/// Shows a small non-dismissible progress dialog with [message] while [work] runs.
Future<T> runWithProgress<T>(
    BuildContext context, Future<T> work, String message) async {
  BuildContext? dialogCtx;
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (c) {
      dialogCtx = c;
      return PopScope(
        canPop: false,
        child: AlertDialog(
          content: Row(children: [
            const CircularProgressIndicator(),
            const SizedBox(width: 20),
            Expanded(child: Text(message)),
          ]),
        ),
      );
    },
  );
  try {
    return await work;
  } finally {
    if (dialogCtx == null) {
      await WidgetsBinding.instance.endOfFrame; // dialog not built yet
    }
    final dc = dialogCtx;
    if (dc != null && dc.mounted) Navigator.of(dc).pop();
  }
}
