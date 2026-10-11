import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../app_theme.dart';
import '../app_ui.dart';
import '../db.dart';
import '../location_service.dart';
import '../models.dart';
import '../report_service.dart';
import '../settings.dart';
import '../widgets.dart';

class LogsScreen extends StatefulWidget {
  const LogsScreen({super.key});

  @override
  State<LogsScreen> createState() => _LogsScreenState();
}

class _LogsScreenState extends State<LogsScreen> {
  final _dayFmt = DateFormat('MM-dd');
  final _timeFmt = DateFormat('HH:mm:ss');
  late DateTime _month;
  List<CheckinLog> _logs = [];
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _month = DateTime(now.year, now.month);
    _load();
  }

  Future<void> _load() async {
    final logs = await AppDb.instance.logsForMonth(_month.year, _month.month);
    if (mounted) setState(() => _logs = logs);
  }

  void _shiftMonth(int delta) {
    setState(() => _month = DateTime(_month.year, _month.month + delta));
    _load();
  }

  Future<void> _send() async {
    if (!AppSettings.telegramConfigured) {
      await showMessage(context, 'Telegram not set up',
          'Add owners in Settings. If the Bot Token is not set, contact the developer.');
      return;
    }
    final key = ReportService.monthKey(_month.year, _month.month);
    if (!await confirm(context, 'Send log to owners',
        'Send the $key report (${_logs.length} check-ins) via Telegram to the owners who receive the monthly report?')) {
      return;
    }
    setState(() => _sending = true);
    try {
      final guard = AppSettings.currentGuard;
      await ReportService.sendMonthReport(_month.year, _month.month,
          sentBy: guard == null ? 'Sent manually' : 'Sent manually by $guard');
      if (mounted) toast(context, 'Sent to owners');
    } catch (e) {
      if (mounted) {
        await showMessage(context, 'Send failed',
            '$e\n\nPlease check the network and Telegram settings.');
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _viewPhoto(CheckinLog l) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            foregroundColor: Colors.white,
            title: Text(
                '${l.checkpointName} · ${DateFormat('yyyy-MM-dd HH:mm').format(l.time)}'),
          ),
          body: Center(
            child: InteractiveViewer(
              child: Image.file(
                File(l.photoPath!),
                errorBuilder: (_, __, ___) => const Text('Photo file not found',
                    style: TextStyle(color: Colors.white)),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final isCurrentMonth = _month.year == now.year && _month.month == now.month;
    final theme = Theme.of(context);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
          child: AppSurface(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
            child: Row(
              children: [
                IconButton(
                    tooltip: 'Previous month',
                    onPressed: () => _shiftMonth(-1),
                    icon: const Icon(Icons.chevron_left)),
                Expanded(
                  child: Column(
                    children: [
                      Text(DateFormat('MMMM yyyy').format(_month),
                          textAlign: TextAlign.center,
                          style: theme.textTheme.titleMedium),
                      Text('${_logs.length} check-ins',
                          style: theme.textTheme.bodySmall),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Next month',
                  onPressed: isCurrentMonth ? null : () => _shiftMonth(1),
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _load,
            child: _logs.isEmpty
                ? ListView(children: const [
                    AppEmptyState(
                      icon: Icons.receipt_long_outlined,
                      title: 'No check-ins this month',
                      message:
                          'Completed checkpoint scans will be listed here.',
                    ),
                  ])
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                    itemCount: _logs.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (_, i) {
                      final l = _logs[i];
                      return AppSurface(
                        child: ListTile(
                          leading: AppIconBox(
                              l.known ? Icons.location_on : Icons.help_outline,
                              color: l.known
                                  ? theme.colorScheme.secondary
                                  : AppColors.warning),
                          title: Text(l.checkpointName),
                          subtitle: Row(
                            children: [
                              Flexible(
                                  child: Text(l.guardName,
                                      overflow: TextOverflow.ellipsis)),
                              if (l.photoPath != null) ...[
                                const SizedBox(width: 8),
                                const Icon(Icons.photo_camera,
                                    size: 16, color: AppColors.success),
                                const Text(' Photo',
                                    style: TextStyle(color: AppColors.success)),
                              ] else if (l.photoMissing) ...[
                                const SizedBox(width: 8),
                                const Icon(Icons.no_photography,
                                    size: 16, color: AppColors.danger),
                                const Text(' Photo MISSING',
                                    style: TextStyle(color: AppColors.danger)),
                              ],
                              if (l.gpsProblem) ...[
                                const SizedBox(width: 8),
                                const Icon(Icons.wrong_location,
                                    size: 16, color: AppColors.danger),
                                Flexible(
                                  child: Text(
                                      ' ${LocationService.label(l.gpsStatus, l.distanceM)}',
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                          color: AppColors.danger)),
                                ),
                              ],
                            ],
                          ),
                          onTap:
                              l.photoPath == null ? null : () => _viewPhoto(l),
                          trailing: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(_dayFmt.format(l.time)),
                              Text(_timeFmt.format(l.time))
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 14),
            child: SizedBox(
              width: double.infinity,
              height: 48,
              child: FilledButton.icon(
                onPressed: _sending ? null : _send,
                icon: _sending
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.send),
                label:
                    Text(_sending ? 'Sending…' : 'Send this month to owners'),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
