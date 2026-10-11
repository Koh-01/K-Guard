import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../app_ui.dart';
import '../db.dart';
import '../location_service.dart';
import '../models.dart';
import '../settings.dart';
import '../widgets.dart';

/// Checkpoint management: register by scanning a tag, set GPS location, rename, delete.
class CheckpointsScreen extends StatefulWidget {
  const CheckpointsScreen({super.key});

  @override
  State<CheckpointsScreen> createState() => _CheckpointsScreenState();
}

class _CheckpointsScreenState extends State<CheckpointsScreen> {
  List<Checkpoint> _items = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final items = await AppDb.instance.checkpoints();
    if (mounted) setState(() => _items = items);
  }

  /// GPS readings less accurate than this aren't saved as a checkpoint position without asking.
  static const _goodAccuracyM = 30.0;

  Future<void> _add() async {
    // Read GPS while the tag is being scanned (registration still works without GPS).
    final gpsFuture = await LocationService.ensurePermission() == null
        ? LocationService.current()
        : null;
    if (!mounted) return;
    final tagId = await scanTagWithUi(context,
        prompt: 'Hold the phone near the NFC tag to register');
    if (tagId == null || !mounted) return;

    final existing = await AppDb.instance.checkpointByTag(tagId);
    if (!mounted) return;
    if (existing != null) {
      await showMessage(context, 'Already registered',
          'This tag is already registered as "${existing.name}".');
      return;
    }
    final name = await editText(context, 'Checkpoint name',
        hint: 'e.g. Block A back door, Car park B2');
    if (name == null || name.isEmpty || !mounted) return;

    final r = gpsFuture == null
        ? null
        : await runWithProgress(context, gpsFuture, 'Recording GPS location…');
    final fix = r?.fix;
    final usable = fix != null && !fix.mocked && fix.accuracy <= _goodAccuracyM;
    await AppDb.instance.addCheckpoint(tagId, name,
        lat: usable ? fix.lat : null, lng: usable ? fix.lng : null);
    await _load();
    if (!mounted) return;
    toast(
        context,
        usable
            ? 'Registered "$name" with GPS location (±${fix.accuracy.round()} m)'
            : 'Registered "$name" without GPS location — use ⋮ → Set location here');
  }

  /// Records the phone's current position as the checkpoint's position.
  Future<void> _setLocation(Checkpoint c) async {
    final r = await runWithProgress(
        context, LocationService.current(), 'Getting GPS location…');
    if (!mounted) return;
    final fix = r.fix;
    if (fix == null) {
      await showMessage(context, 'No GPS location',
          r.error ?? 'Could not get a GPS position.');
      return;
    }
    if (fix.mocked) {
      await showMessage(context, 'Fake GPS detected',
          'Turn off any fake-location app and try again.');
      return;
    }
    if (fix.accuracy > _goodAccuracyM &&
        !await confirm(
            context,
            'Low GPS accuracy',
            'Accuracy is only ±${fix.accuracy.round()} m. For best results stand right at '
                'the tag in the open and try again.\n\nSave this location anyway?')) {
      return;
    }
    await AppDb.instance.setCheckpointLocation(c.id!, fix.lat, fix.lng);
    await _load();
    if (mounted) {
      toast(context,
          'GPS location saved for "${c.name}" (±${fix.accuracy.round()} m)');
    }
  }

  Future<void> _reorder(int oldIndex, int newIndex) async {
    setState(() => _items.insert(newIndex, _items.removeAt(oldIndex)));
    await AppDb.instance.reorderCheckpoints([for (final c in _items) c.id!]);
  }

  Future<void> _rename(Checkpoint c) async {
    final name = await editText(context, 'Rename checkpoint', initial: c.name);
    if (name == null || name.isEmpty) return;
    await AppDb.instance.renameCheckpoint(c.id!, name);
    await _load();
  }

  Future<void> _delete(Checkpoint c) async {
    if (!await confirm(context, 'Delete checkpoint',
        'Delete "${c.name}"? Existing check-in records are kept.')) {
      return;
    }
    await AppDb.instance.deleteCheckpoint(c.id!);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Checkpoints')),
      floatingActionButton: _items.isEmpty
          ? null
          : FloatingActionButton.extended(
              onPressed: _add,
              icon: const Icon(Icons.add),
              label: const Text('Scan to add'),
            ),
      body: _items.isEmpty
          ? AppEmptyState(
              icon: Icons.nfc_outlined,
              title: 'No checkpoints yet',
              message:
                  'Place an NFC tag at each patrol point, then scan it to register the location.',
              action: FilledButton.icon(
                onPressed: _add,
                icon: const Icon(Icons.add),
                label: const Text('Scan first tag'),
              ),
            )
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: AppSurface(
                    color: Theme.of(context).colorScheme.secondaryContainer,
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.info_outline,
                            size: 19,
                            color: Theme.of(context).colorScheme.secondary),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            AppSettings.enforceOrder
                                ? 'Patrol order is enforced. Drag the handle to change the route.'
                                : 'Drag the handle to arrange the route. Order enforcement is available in Developer settings.',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  child: ReorderableListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
                    buildDefaultDragHandles: false,
                    itemCount: _items.length,
                    onReorderItem: _reorder,
                    itemBuilder: (_, i) {
                      final c = _items[i];
                      return Padding(
                        key: ValueKey(c.id),
                        padding: const EdgeInsets.only(bottom: 10),
                        child: AppSurface(
                          child: ListTile(
                            isThreeLine: true,
                            leading: Container(
                              width: 40,
                              height: 40,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: Theme.of(context)
                                    .colorScheme
                                    .surfaceContainerHigh,
                                borderRadius: BorderRadius.circular(9),
                              ),
                              child: Text('${i + 1}',
                                  style:
                                      Theme.of(context).textTheme.titleMedium),
                            ),
                            title: Text(c.name),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(c.tagId,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        fontFamily: 'monospace', fontSize: 12)),
                                const SizedBox(height: 4),
                                AppStatusPill(
                                  label: c.hasLocation
                                      ? 'GPS location set'
                                      : 'GPS not set',
                                  icon: c.hasLocation
                                      ? Icons.location_on
                                      : Icons.location_off,
                                  color: c.hasLocation
                                      ? AppColors.success
                                      : AppColors.warning,
                                ),
                              ],
                            ),
                            onTap: () => _rename(c),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                PopupMenuButton<String>(
                                  onSelected: (v) => switch (v) {
                                    'rename' => _rename(c),
                                    'location' => _setLocation(c),
                                    _ => _delete(c),
                                  },
                                  itemBuilder: (_) => [
                                    const PopupMenuItem(
                                        value: 'rename',
                                        child: ListTile(
                                            leading: Icon(Icons.edit_outlined),
                                            title: Text('Rename'))),
                                    PopupMenuItem(
                                        value: 'location',
                                        child: ListTile(
                                            leading:
                                                const Icon(Icons.my_location),
                                            title: Text(c.hasLocation
                                                ? 'Update location'
                                                : 'Set location here'))),
                                    const PopupMenuItem(
                                        value: 'delete',
                                        child: ListTile(
                                            leading: Icon(Icons.delete_outline),
                                            title: Text('Delete'))),
                                  ],
                                ),
                                ReorderableDragStartListener(
                                  index: i,
                                  child: const Padding(
                                    padding: EdgeInsets.all(8),
                                    child: Icon(Icons.drag_handle),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }
}
