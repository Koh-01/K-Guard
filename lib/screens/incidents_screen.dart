import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../app_theme.dart';
import '../app_ui.dart';
import '../db.dart';
import '../incident_categories.dart';
import '../incident_service.dart';
import '../models.dart';
import '../widgets.dart';
import 'incident_form_screen.dart';

/// Opens the incident form; returns true if an incident was submitted.
Future<bool> openIncidentForm(BuildContext context,
    {String? category, String? location}) async {
  final r = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
          builder: (_) => IncidentFormScreen(
              initialCategory: category, initialLocation: location)));
  return r ?? false;
}

class IncidentsScreen extends StatefulWidget {
  const IncidentsScreen({super.key});

  @override
  State<IncidentsScreen> createState() => _IncidentsScreenState();
}

class _IncidentsScreenState extends State<IncidentsScreen> {
  final _fmt = DateFormat('yyyy-MM-dd HH:mm');
  List<Incident> _items = [];

  @override
  void initState() {
    super.initState();
    _load();
    IncidentService.sending.addListener(_load);
  }

  @override
  void dispose() {
    IncidentService.sending.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    final items = await AppDb.instance.recentIncidents();
    if (mounted) setState(() => _items = items);
  }

  Future<void> _report() async {
    if (await openIncidentForm(context)) await _load();
  }

  Future<void> _resend(Incident i) async {
    try {
      await IncidentService.send(i.id!);
      if (mounted) toast(context, 'Sent to all owners');
    } catch (e) {
      if (mounted) await showMessage(context, 'Send failed', '$e');
    }
    await _load();
  }

  void _open(Incident i) {
    final c = categoryById(i.category);
    final sent = IncidentService.fullySent(i);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        builder: (_, scroll) => ListView(
          controller: scroll,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
          children: [
            Row(children: [
              Icon(c.icon, size: 32),
              const SizedBox(width: 12),
              Expanded(
                  child:
                      Text(c.label, style: Theme.of(ctx).textTheme.titleLarge)),
            ]),
            const SizedBox(height: 12),
            if (i.location != null)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const AppIconBox(Icons.place_outlined),
                title: const Text('Location'),
                subtitle: Text(i.location!),
              ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const AppIconBox(Icons.badge_outlined),
              title: const Text('Reported by'),
              subtitle: Text(i.guardName),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const AppIconBox(Icons.schedule_outlined),
              title: const Text('Time'),
              subtitle: Text(_fmt.format(i.time)),
            ),
            const SizedBox(height: 12),
            if (i.description.isNotEmpty) Text(i.description),
            const SizedBox(height: 16),
            if (i.photoPaths.isNotEmpty)
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final p in i.photoPaths)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.file(File(p),
                        width: 140,
                        height: 140,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const SizedBox(
                            width: 140,
                            height: 140,
                            child: Icon(Icons.broken_image))),
                  ),
              ]),
            if (i.videoPath != null)
              const ListTile(
                  leading: Icon(Icons.videocam), title: Text('Video attached')),
            if (i.voicePath != null)
              const ListTile(
                  leading: Icon(Icons.mic), title: Text('Voice note attached')),
            const Divider(),
            ListTile(
              leading: Icon(sent ? Icons.done_all : Icons.schedule_send,
                  color: sent ? AppColors.success : AppColors.warning),
              title: Text(sent
                  ? 'Sent to all owners'
                  : 'Sent to ${IncidentService.recipients().where((o) => i.sentTo.contains(o.chatId)).length} '
                      'of ${IncidentService.recipients().length} owners'),
              trailing: sent
                  ? null
                  : FilledButton(
                      onPressed: () {
                        Navigator.pop(ctx);
                        _resend(i);
                      },
                      child: const Text('Send now'),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.danger,
        foregroundColor: Colors.white,
        onPressed: _report,
        icon: const Icon(Icons.add),
        label: const Text('New report'),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
            child: AppSectionHeader(
              'Incident reports',
              caption: _items.isEmpty
                  ? 'No reports on this device'
                  : '${_items.length} recent ${_items.length == 1 ? 'report' : 'reports'}',
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _load,
              child: _items.isEmpty
                  ? ListView(
                      children: const [
                        AppEmptyState(
                          icon: Icons.verified_user_outlined,
                          title: 'No incidents reported',
                          message:
                              'New incident reports and delivery status will appear here.',
                        ),
                      ],
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(20, 4, 20, 96),
                      itemCount: _items.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (_, idx) {
                        final i = _items[idx];
                        final c = categoryById(i.category);
                        final sent = IncidentService.fullySent(i);
                        final uploading =
                            IncidentService.sending.value.contains(i.id);
                        return AppSurface(
                          child: ListTile(
                            leading:
                                AppIconBox(c.icon, color: AppColors.danger),
                            title: Text(c.label),
                            subtitle: Text(
                              [
                                i.guardName,
                                if (i.location != null) i.location!,
                                if (i.description.isNotEmpty) i.description
                              ].join(' · '),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(DateFormat('MM-dd HH:mm').format(i.time),
                                    style:
                                        Theme.of(context).textTheme.bodySmall),
                                const SizedBox(height: 5),
                                uploading
                                    ? const SizedBox(
                                        width: 15,
                                        height: 15,
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2))
                                    : AppStatusPill(
                                        label: sent ? 'Sent' : 'Pending',
                                        icon: sent
                                            ? Icons.done_all
                                            : Icons.schedule_send,
                                        color: sent
                                            ? AppColors.success
                                            : AppColors.warning,
                                      ),
                              ],
                            ),
                            onTap: () => _open(i),
                          ),
                        );
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
