import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../app_theme.dart';
import '../app_ui.dart';
import '../cleanup_service.dart';
import '../db.dart';
import '../incident_categories.dart';
import '../incident_service.dart';
import '../models.dart';
import '../settings.dart';
import '../widgets.dart';
import 'camera_screen.dart';

const _maxPhotos = 3;
const _maxVoice = Duration(minutes: 2);

/// Form for a guard to report an incident. Media is captured live only (no gallery).
class IncidentFormScreen extends StatefulWidget {
  final String? initialCategory;
  final String? initialLocation;

  const IncidentFormScreen(
      {super.key, this.initialCategory, this.initialLocation});

  @override
  State<IncidentFormScreen> createState() => _IncidentFormScreenState();
}

class _IncidentFormScreenState extends State<IncidentFormScreen> {
  final _desc = TextEditingController();
  final _recorder = AudioRecorder();

  String? _category;
  String _location = '';
  List<String> _checkpointNames = [];

  /// 'video' or 'photo'
  String _mode = 'photo';
  String? _video;
  final List<String> _photos = [];
  String? _voice;

  bool _recordingVoice = false;
  Duration _voiceLength = Duration.zero;
  Timer? _voiceTimer;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _category = widget.initialCategory;
    _location = widget.initialLocation ?? '';
    AppDb.instance.checkpoints().then((cps) {
      if (mounted) {
        setState(() => _checkpointNames = cps.map((c) => c.name).toList());
      }
    });
  }

  @override
  void dispose() {
    _voiceTimer?.cancel();
    _recorder.dispose();
    _desc.dispose();
    super.dispose();
  }

  bool get _hasMedia => _video != null || _photos.isNotEmpty || _voice != null;
  bool get _dirty =>
      _category != widget.initialCategory ||
      _hasMedia ||
      _desc.text.trim().isNotEmpty ||
      _location != (widget.initialLocation ?? '');

  String _fmt(Duration d) =>
      '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

  Future<void> _setMode(String mode) async {
    if (mode == _mode) return;
    if (_hasMedia &&
        !await confirm(context, 'Switch evidence type?',
            'The video / photos / voice note already captured will be discarded.')) {
      return;
    }
    if (_recordingVoice) await _recorder.cancel();
    _voiceTimer?.cancel();
    setState(() {
      _mode = mode;
      _video = null;
      _photos.clear();
      _voice = null;
      _recordingVoice = false;
    });
  }

  Future<void> _recordVideo() async {
    final path = await Navigator.push<String>(
      context,
      MaterialPageRoute(
          builder: (_) =>
              const CameraScreen(title: 'Record incident video', video: true)),
    );
    if (path != null && mounted) setState(() => _video = path);
  }

  Future<void> _takePhoto() async {
    final path = await Navigator.push<String>(
      context,
      MaterialPageRoute(
          builder: (_) => const CameraScreen(title: 'Incident photo')),
    );
    if (path != null && mounted) setState(() => _photos.add(path));
  }

  Future<void> _toggleVoice() async {
    if (_recordingVoice) {
      _voiceTimer?.cancel();
      final path = await _recorder.stop();
      if (mounted) {
        setState(() {
          _recordingVoice = false;
          _voice = path;
        });
      }
      return;
    }
    if (!await _recorder.hasPermission()) {
      if (mounted) {
        await showMessage(context, 'Microphone permission needed',
            'Please allow microphone access for this app in system settings.');
      }
      return;
    }
    final path = p.join((await getTemporaryDirectory()).path,
        'voice_${DateTime.now().millisecondsSinceEpoch}.m4a');
    await _recorder.start(
        const RecordConfig(
            encoder: AudioEncoder.aacLc,
            bitRate: 48000,
            sampleRate: 22050,
            numChannels: 1),
        path: path);
    _voiceLength = Duration.zero;
    _voiceTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() => _voiceLength += const Duration(seconds: 1));
      if (_voiceLength >= _maxVoice) _toggleVoice();
    });
    setState(() {
      _recordingVoice = true;
      _voice = null;
    });
  }

  /// Copies captured media into permanent app storage.
  Future<String> _keep(String src, String dirPath, String name) async {
    final dest = p.join(dirPath, '$name${p.extension(src)}');
    await File(src).copy(dest);
    try {
      await File(src).delete();
    } catch (_) {}
    return dest;
  }

  Future<void> _submit() async {
    final category = _category;
    final desc = _desc.text.trim();
    if (category == null) {
      toast(context, 'Choose a category');
      return;
    }
    if (category == 'other' && desc.isEmpty) {
      toast(context, 'Please describe the incident for "Other"');
      return;
    }
    if (_mode == 'video' && _video == null) {
      toast(context, 'Evidence required: record a video');
      return;
    }
    if (_mode == 'photo' && _photos.isEmpty) {
      toast(context, 'Evidence required: take at least one photo');
      return;
    }
    if (_recordingVoice) await _toggleVoice();

    setState(() => _submitting = true);
    try {
      final now = DateTime.now();
      final dir = await CleanupService.incidentMediaDir();
      await dir.create(recursive: true);
      final stamp = now.millisecondsSinceEpoch;
      final incident = Incident(
        time: now,
        guardName: AppSettings.currentGuard ?? 'Unknown',
        category: category,
        location: _location.trim().isEmpty ? null : _location.trim(),
        description: desc,
        mediaType: _mode,
        videoPath: _video == null
            ? null
            : await _keep(_video!, dir.path, 'incident_${stamp}_video'),
        photoPaths: [
          for (var i = 0; i < _photos.length; i++)
            await _keep(
                _photos[i], dir.path, 'incident_${stamp}_photo${i + 1}'),
        ],
        voicePath: _voice == null
            ? null
            : await _keep(_voice!, dir.path, 'incident_${stamp}_voice'),
      );
      final id = await AppDb.instance.addIncident(incident);

      // Upload in the background so the guard can carry on immediately.
      if (AppSettings.telegramConfigured &&
          IncidentService.recipients().isEmpty) {
        showGlobalToast(
            'Incident saved. No owner has "Incident reports" switched on, so nobody was notified.');
      } else if (AppSettings.telegramConfigured) {
        IncidentService.sendInBackground(id);
        showGlobalToast(
            '📤 Incident saved — sending to owners in the background…');
      } else {
        showGlobalToast(
            'Incident saved. Telegram is not set up, so owners were not notified.');
      }
      if (!mounted) return;
      if (mounted) Navigator.pop(context, true);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Widget _section(String text) => Padding(
        padding: const EdgeInsets.only(top: 28, bottom: 10),
        child: Text(text, style: Theme.of(context).textTheme.titleMedium),
      );

  Widget _categoryGrid() {
    final scheme = Theme.of(context).colorScheme;
    return GridView.count(
      crossAxisCount: 3,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      childAspectRatio: 1.05,
      children: [
        for (final c in incidentCategories)
          Material(
            color: _category == c.id ? scheme.primaryContainer : scheme.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(
                  color: _category == c.id
                      ? scheme.secondary
                      : scheme.outlineVariant,
                  width: _category == c.id ? 2 : 1),
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => setState(() => _category = c.id),
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(c.icon,
                        size: 32,
                        color: _category == c.id ? scheme.secondary : null),
                    const SizedBox(height: 6),
                    Text(c.label,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        style: const TextStyle(fontSize: 12)),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _videoEvidence() {
    if (_video == null) {
      return OutlinedButton.icon(
        onPressed: _recordVideo,
        icon: const Icon(Icons.videocam),
        label: const Text('Record video (max 60 s)'),
      );
    }
    return AppSurface(
      child: ListTile(
        leading:
            const AppIconBox(Icons.videocam_outlined, color: AppColors.success),
        title: const Text('Video recorded'),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Record again',
              onPressed: _recordVideo),
          IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: () => setState(() => _video = null)),
        ]),
      ),
    );
  }

  Widget _photoVoiceEvidence() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text('At least 1 photo required (max $_maxPhotos)',
              style: TextStyle(
                  fontSize: 12,
                  color: _photos.isEmpty
                      ? AppColors.danger
                      : Theme.of(context).colorScheme.onSurfaceVariant)),
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (var i = 0; i < _photos.length; i++)
              Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.file(File(_photos[i]),
                        width: 96, height: 96, fit: BoxFit.cover),
                  ),
                  Positioned(
                    right: 0,
                    top: 0,
                    child: InkWell(
                      onTap: () => setState(() => _photos.removeAt(i)),
                      child: const CircleAvatar(
                          radius: 12, child: Icon(Icons.close, size: 16)),
                    ),
                  ),
                ],
              ),
            if (_photos.length < _maxPhotos)
              SizedBox(
                width: 96,
                height: 96,
                child: OutlinedButton(
                  onPressed: _takePhoto,
                  style: OutlinedButton.styleFrom(padding: EdgeInsets.zero),
                  child: const Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.add_a_photo),
                      SizedBox(height: 4),
                      Text('Photo', style: TextStyle(fontSize: 12))
                    ],
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        AppSurface(
          child: ListTile(
            leading: Icon(_recordingVoice ? Icons.stop_circle : Icons.mic,
                color: _recordingVoice
                    ? AppColors.danger
                    : (_voice != null ? AppColors.success : null),
                size: 32),
            title: Text(_recordingVoice
                ? 'Recording… ${_fmt(_voiceLength)} (tap to stop)'
                : _voice != null
                    ? 'Voice note recorded (${_fmt(_voiceLength)})'
                    : 'Tap to record a voice note'),
            subtitle: Text('Optional · max ${_fmt(_maxVoice)}'),
            onTap: _toggleVoice,
            trailing: _voice != null && !_recordingVoice
                ? IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => setState(() => _voice = null))
                : null,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop || _submitting) return;
        if (await confirm(context, 'Discard report?',
                'The incident has not been submitted.') &&
            context.mounted) {
          if (_recordingVoice) await _recorder.cancel();
          if (context.mounted) Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('Report Incident')),
        body: AbsorbPointer(
          absorbing: _submitting,
          child: LayoutBuilder(
            builder: (context, constraints) => ListView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
              children: [
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 720),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _section('1. What happened? (required)'),
                        _categoryGrid(),
                        _section('2. Where? (optional)'),
                        Autocomplete<String>(
                          initialValue: TextEditingValue(text: _location),
                          optionsBuilder: (v) {
                            final q = v.text.trim().toLowerCase();
                            return q.isEmpty
                                ? _checkpointNames
                                : _checkpointNames
                                    .where((n) => n.toLowerCase().contains(q));
                          },
                          onSelected: (v) => setState(() => _location = v),
                          fieldViewBuilder:
                              (context, controller, focusNode, onSubmit) =>
                                  TextField(
                            controller: controller,
                            focusNode: focusNode,
                            textCapitalization: TextCapitalization.sentences,
                            decoration: const InputDecoration(
                              isDense: true,
                              prefixIcon: Icon(Icons.place_outlined),
                              hintText:
                                  'e.g. Behind Block C, near the back gate',
                            ),
                            onChanged: (v) => setState(() => _location = v),
                            onSubmitted: (_) => onSubmit(),
                          ),
                        ),
                        _section('3. Evidence (required)'),
                        SegmentedButton<String>(
                          segments: const [
                            ButtonSegment(
                                value: 'video',
                                icon: Icon(Icons.videocam),
                                label: Text('Video')),
                            ButtonSegment(
                                value: 'photo',
                                icon: Icon(Icons.photo_camera),
                                label: Text('Photo + Voice')),
                          ],
                          selected: {_mode},
                          onSelectionChanged: (s) => _setMode(s.first),
                        ),
                        const SizedBox(height: 12),
                        _mode == 'video'
                            ? _videoEvidence()
                            : _photoVoiceEvidence(),
                        _section(_category == 'other'
                            ? '4. Description (required)'
                            : '4. Description'),
                        TextField(
                          controller: _desc,
                          minLines: 3,
                          maxLines: 6,
                          maxLength: 1000,
                          textCapitalization: TextCapitalization.sentences,
                          decoration: const InputDecoration(
                            hintText: 'Describe the problem…',
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          height: 52,
                          child: FilledButton.icon(
                            onPressed: _submitting ? null : _submit,
                            icon: _submitting
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2))
                                : const Icon(Icons.send),
                            label: Text(_submitting
                                ? 'Saving…'
                                : 'Submit & send to owners'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
