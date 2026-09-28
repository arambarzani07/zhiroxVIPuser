import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:zhirox/features/expiry/expiry_date_parser.dart';

class ExpiryDateScanner extends StatefulWidget {
  const ExpiryDateScanner({super.key});

  @override
  State<ExpiryDateScanner> createState() => _ExpiryDateScannerState();
}

class _ExpiryDateScannerState extends State<ExpiryDateScanner>
    with WidgetsBindingObserver {
  CameraController? _camera;
  CameraDescription? _description;
  final _recognizer = TextRecognizer(script: TextRecognitionScript.latin);
  List<DateTime> _candidates = const [];
  String? _error;
  bool _busy = false;
  bool _starting = false;
  bool _disposed = false;
  DateTime? _lastFrame;
  DateTime? _focusReadyAt;
  Offset _focusPoint = const Offset(0.5, 0.5);
  double _zoom = 1;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_start());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      unawaited(_release());
    } else if (state == AppLifecycleState.resumed &&
        _camera == null &&
        _candidates.isEmpty) {
      unawaited(_start());
    }
  }

  Future<void> _release() async {
    final camera = _camera;
    _camera = null;
    if (camera != null) {
      try {
        await camera.dispose();
      } catch (_) {}
    }
  }

  Future<void> _start() async {
    if (_disposed || _camera != null || _starting) return;
    _starting = true;
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        throw CameraException('no_camera', 'No camera');
      }
      final description = cameras.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      final controller = CameraController(
        description,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: Platform.isAndroid
            ? ImageFormatGroup.nv21
            : ImageFormatGroup.bgra8888,
      );
      await controller.initialize();
      if (_disposed ||
          !mounted ||
          WidgetsBinding.instance.lifecycleState == AppLifecycleState.paused ||
          WidgetsBinding.instance.lifecycleState ==
              AppLifecycleState.inactive) {
        await controller.dispose();
        return;
      }
      _description = description;
      _camera = controller;
      setState(() => _error = null);
      // The small print is often held close to the lens. Ask the camera to
      // focus at the label before handing frames to text recognition.
      await _focus(const Offset(0.5, 0.5));
      await controller.startImageStream(_readFrame);
    } catch (_) {
      await _release();
      if (mounted) {
        setState(() => _error = 'کامێرا نەکرایەوە. مۆڵەتی کامێرا بپشکنە.');
      }
    } finally {
      _starting = false;
    }
  }

  Future<void> _focus(Offset point) async {
    final camera = _camera;
    if (camera == null || !camera.value.isInitialized) return;
    _focusReadyAt = DateTime.now().add(const Duration(milliseconds: 700));
    if (mounted) setState(() => _focusPoint = point);
    try {
      await camera.setFocusMode(FocusMode.auto);
      await camera.setFocusPoint(point);
      await camera.setExposurePoint(point);
    } on CameraException {
      // Some lenses do not expose point focus. Continuous autofocus remains
      // available, and the user can still move the package farther away.
    }
  }

  Future<void> _setZoom(double requested) async {
    final camera = _camera;
    if (camera == null || !camera.value.isInitialized) return;
    try {
      final min = await camera.getMinZoomLevel();
      final max = await camera.getMaxZoomLevel();
      final level = requested.clamp(min, max);
      await camera.setZoomLevel(level);
      if (mounted) setState(() => _zoom = level);
      await _focus(_focusPoint);
    } on CameraException {
      // Leave the current zoom intact when unsupported by the device.
    }
  }

  InputImage? _input(CameraImage image) {
    final description = _description;
    final camera = _camera;
    if (description == null || camera == null || image.planes.length != 1) {
      return null;
    }
    final format = InputImageFormatValue.fromRawValue(image.format.raw);
    if ((Platform.isIOS && format != InputImageFormat.bgra8888) ||
        (Platform.isAndroid && format != InputImageFormat.nv21)) {
      return null;
    }
    const orientations = {
      DeviceOrientation.portraitUp: 0,
      DeviceOrientation.landscapeLeft: 90,
      DeviceOrientation.portraitDown: 180,
      DeviceOrientation.landscapeRight: 270,
    };
    var rotation = description.sensorOrientation;
    if (Platform.isAndroid) {
      final compensation = orientations[camera.value.deviceOrientation];
      if (compensation == null) return null;
      rotation = description.lensDirection == CameraLensDirection.front
          ? (rotation + compensation) % 360
          : (rotation - compensation + 360) % 360;
    }
    final imageRotation = InputImageRotationValue.fromRawValue(rotation);
    if (format == null || imageRotation == null) return null;
    final plane = image.planes.first;
    return InputImage.fromBytes(
      bytes: plane.bytes,
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: imageRotation,
        format: format,
        bytesPerRow: plane.bytesPerRow,
      ),
    );
  }

  void _readFrame(CameraImage frame) {
    final now = DateTime.now();
    if (_disposed ||
        _busy ||
        _candidates.isNotEmpty ||
        (_focusReadyAt != null && now.isBefore(_focusReadyAt!)) ||
        (_lastFrame != null &&
            now.difference(_lastFrame!).inMilliseconds < 500)) {
      return;
    }
    final input = _input(frame);
    if (input == null) return;
    _busy = true;
    _lastFrame = now;
    unawaited(_recognize(input));
  }

  Future<void> _recognize(InputImage input) async {
    try {
      final text = await _recognizer.processImage(input);
      final dates = ExpiryDateParser.candidates(text.text);
      if (dates.isNotEmpty && mounted && !_disposed) {
        final camera = _camera;
        if (camera != null && camera.value.isStreamingImages) {
          await camera.stopImageStream();
        }
        if (mounted) setState(() => _candidates = dates);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'بەروار نەخوێندرایەوە؛ دووبارە هەوڵ بدە.');
      }
    } finally {
      _busy = false;
    }
  }

  Future<void> _retry() async {
    setState(() {
      _candidates = const [];
      _error = null;
    });
    final camera = _camera;
    if (camera != null &&
        camera.value.isInitialized &&
        !camera.value.isStreamingImages) {
      await _focus(_focusPoint);
      await camera.startImageStream(_readFrame);
    } else if (camera == null) {
      await _start();
    } else {
      await _focus(_focusPoint);
    }
  }

  @override
  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_release());
    unawaited(_recognizer.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final camera = _camera;
    return Scaffold(
      appBar: AppBar(title: const Text('خوێندنەوەی بەرواری بەسەرچوون')),
      body: Column(
        children: [
          Expanded(
            child: camera != null && camera.value.isInitialized
                ? LayoutBuilder(
                    builder: (context, constraints) => GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTapDown: (tap) => unawaited(
                        _focus(
                          Offset(
                            (tap.localPosition.dx / constraints.maxWidth).clamp(
                              0.0,
                              1.0,
                            ),
                            (tap.localPosition.dy / constraints.maxHeight)
                                .clamp(0.0, 1.0),
                          ),
                        ),
                      ),
                      child: Stack(
                        children: [
                          Positioned.fill(child: CameraPreview(camera)),
                          Positioned(
                            left: constraints.maxWidth * _focusPoint.dx - 18,
                            top: constraints.maxHeight * _focusPoint.dy - 18,
                            child: const IgnorePointer(
                              child: Icon(
                                Icons.center_focus_strong,
                                color: Colors.white,
                                size: 36,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                : Center(
                    child: _error == null
                        ? const CircularProgressIndicator()
                        : Text(_error!, textAlign: TextAlign.center),
                  ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'دەقەکە ١٥–٢٠ سم لە کامێرا دوور ڕابگرە و لەسەر بەرواری EXP تێپ بکە تا فوکەس بکرێت. پێش پاشەکەوتکردن پشتڕاستی بکەرەوە.',
                  ),
                  if (_candidates.isEmpty)
                    Wrap(
                      spacing: 8,
                      children: [
                        ChoiceChip(
                          label: const Text('١×'),
                          selected: _zoom < 1.5,
                          onSelected: (_) => unawaited(_setZoom(1)),
                        ),
                        ChoiceChip(
                          label: const Text('٢× · بۆ دەقی بچووک'),
                          selected: _zoom >= 1.5,
                          onSelected: (_) => unawaited(_setZoom(2)),
                        ),
                        IconButton(
                          tooltip: 'دووبارە فوکەس بکە',
                          onPressed: () => unawaited(_focus(_focusPoint)),
                          icon: const Icon(Icons.center_focus_strong),
                        ),
                      ],
                    ),
                  if (_candidates.isEmpty)
                    TextButton.icon(
                      onPressed: _retry,
                      icon: const Icon(Icons.refresh),
                      label: const Text('دووبارە هەوڵ بدە'),
                    )
                  else ...[
                    for (final date in _candidates.take(4))
                      ListTile(
                        leading: const Icon(Icons.event_available),
                        title: Text('${date.year}/${date.month}/${date.day}'),
                        subtitle: const Text('بەرواری دۆزراو پشتڕاست بکەرەوە'),
                        onTap: () => Navigator.of(context).pop(date),
                      ),
                    TextButton(
                      onPressed: _retry,
                      child: const Text(
                        'بەروارەکە دروست نییە؛ دووبارە بخوێنەوە',
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
