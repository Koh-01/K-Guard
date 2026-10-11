import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../widgets.dart';

/// In-app camera for photo proof and incident evidence. There is deliberately no gallery option:
/// photos and videos must be captured live. Returns the captured file path, or null if cancelled.
class CameraScreen extends StatefulWidget {
  final String title;

  /// Record a video instead of taking a photo.
  final bool video;

  /// Maximum video length; recording stops automatically.
  final Duration maxVideo;

  /// Ask for confirmation before leaving without a capture (used for photo proof).
  final String? skipWarning;

  const CameraScreen({
    super.key,
    required this.title,
    this.video = false,
    this.maxVideo = const Duration(seconds: 60),
    this.skipWarning,
  });

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  CameraController? _controller;
  String? _error;
  String? _captured;
  bool _busy = false;
  bool _recording = false;
  Duration _elapsed = Duration.zero;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        throw CameraException('none', 'No camera found on this device');
      }
      final back = cameras.firstWhere(
          (c) => c.lensDirection == CameraLensDirection.back,
          orElse: () => cameras.first);
      // Videos use a lower resolution so a 60 s clip stays well under Telegram's 50 MB upload limit.
      // Video: 480p at ~1.2 Mbps ≈ 9 MB per minute — fast to upload on mobile data,
      // still clear enough to see the problem. (Default bitrates can be 5-10x larger.)
      final c = widget.video
          ? CameraController(back, ResolutionPreset.medium,
              enableAudio: true,
              fps: 30,
              videoBitrate: 1200000,
              audioBitrate: 64000)
          : CameraController(back, ResolutionPreset.high, enableAudio: false);
      await c.initialize();
      if (!mounted) {
        await c.dispose();
        return;
      }
      setState(() => _controller = c);
    } on CameraException catch (e) {
      if (mounted) {
        setState(() => _error = e.code.contains('AccessDenied')
            ? 'Camera or microphone permission denied. Please allow access for this app in system settings.'
            : 'Camera error: ${e.description ?? e.code}');
      }
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _shoot() async {
    final c = _controller;
    if (c == null || _busy || c.value.isTakingPicture) return;
    setState(() => _busy = true);
    try {
      final file = await c.takePicture();
      if (mounted) setState(() => _captured = file.path);
    } on CameraException catch (e) {
      if (mounted) {
        toast(context, 'Failed to take photo: ${e.description ?? e.code}');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _toggleRecording() async {
    final c = _controller;
    if (c == null || _busy) return;
    setState(() => _busy = true);
    try {
      if (!_recording) {
        await c.startVideoRecording();
        _elapsed = Duration.zero;
        _timer = Timer.periodic(const Duration(seconds: 1), (_) {
          setState(() => _elapsed += const Duration(seconds: 1));
          if (_elapsed >= widget.maxVideo) _toggleRecording();
        });
        setState(() => _recording = true);
      } else {
        _timer?.cancel();
        final file = await c.stopVideoRecording();
        if (mounted) {
          setState(() {
            _recording = false;
            _captured = file.path;
          });
        }
      }
    } on CameraException catch (e) {
      _timer?.cancel();
      if (mounted) {
        setState(() => _recording = false);
        toast(context, 'Recording failed: ${e.description ?? e.code}');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _leave() async {
    if (_recording) return;
    final warning = widget.skipWarning;
    if (warning != null && !await confirm(context, 'Skip?', warning)) return;
    if (mounted) Navigator.pop(context);
  }

  String _fmt(Duration d) =>
      '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

  Widget _preview(CameraController c) {
    final captured = _captured;
    if (captured == null) return CameraPreview(c);
    if (!widget.video) return Image.file(File(captured));
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.videocam, color: Colors.white, size: 72),
        const SizedBox(height: 12),
        Text('Video recorded (${_fmt(_elapsed)})',
            style: const TextStyle(color: Colors.white, fontSize: 18)),
      ],
    );
  }

  Widget _shutter() {
    if (!widget.video) {
      return GestureDetector(
        onTap: _shoot,
        child: Container(
          width: 76,
          height: 76,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 5),
            color: _busy ? Colors.grey : Colors.white24,
          ),
        ),
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          _recording
              ? '● ${_fmt(_elapsed)} / ${_fmt(widget.maxVideo)}'
              : 'Max ${_fmt(widget.maxVideo)}',
          style:
              TextStyle(color: _recording ? AppColors.danger : Colors.white70),
        ),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: _toggleRecording,
          child: Container(
            width: 76,
            height: 76,
            padding: EdgeInsets.all(_recording ? 22 : 8),
            decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 5)),
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.danger,
                shape: _recording ? BoxShape.rectangle : BoxShape.circle,
                borderRadius: _recording ? BorderRadius.circular(4) : null,
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _leave();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          automaticallyImplyLeading: false,
          title: Text(widget.title),
          actions: [
            TextButton(
              onPressed: _recording ? null : _leave,
              child: Text(widget.skipWarning != null ? 'Skip' : 'Cancel',
                  style: const TextStyle(color: Colors.white70)),
            ),
          ],
        ),
        body: _error != null
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(_error!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white)),
                ),
              )
            : c == null
                ? const Center(
                    child: CircularProgressIndicator(color: Colors.white))
                : Column(
                    children: [
                      Expanded(child: Center(child: _preview(c))),
                      SafeArea(
                        top: false,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              vertical: 20, horizontal: 24),
                          child: _captured == null
                              ? Center(child: _shutter())
                              : Row(
                                  children: [
                                    Expanded(
                                      child: OutlinedButton.icon(
                                        style: OutlinedButton.styleFrom(
                                            foregroundColor: Colors.white),
                                        onPressed: () =>
                                            setState(() => _captured = null),
                                        icon: const Icon(Icons.refresh),
                                        label: const Text('Retake'),
                                      ),
                                    ),
                                    const SizedBox(width: 16),
                                    Expanded(
                                      child: FilledButton.icon(
                                        style: FilledButton.styleFrom(
                                          backgroundColor: Colors.white,
                                          foregroundColor: AppColors.ink,
                                        ),
                                        onPressed: () =>
                                            Navigator.pop(context, _captured),
                                        icon: const Icon(Icons.check),
                                        label: Text(widget.video
                                            ? 'Use video'
                                            : 'Use photo'),
                                      ),
                                    ),
                                  ],
                                ),
                        ),
                      ),
                    ],
                  ),
      ),
    );
  }
}
