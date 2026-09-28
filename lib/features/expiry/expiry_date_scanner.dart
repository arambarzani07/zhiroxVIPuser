import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:zhirox/features/expiry/expiry_date_parser.dart';
import 'package:zhirox/features/expiry/expiry_frame_crop.dart';

class ExpiryDateScanner extends StatefulWidget {
  const ExpiryDateScanner({super.key});

  @override
  State<ExpiryDateScanner> createState() => _ExpiryDateScannerState();
}

class _ExpiryDateScannerState extends State<ExpiryDateScanner>
    with WidgetsBindingObserver {
  CameraController? _camera;
  CameraDescription? _description;
  List<CameraDescription> _backCameras = const [];
  CameraDescription? _selectedCamera;
  final _recognizer = TextRecognizer(script: TextRecognitionScript.latin);
  List<DateTime> _candidates = const [];
  String? _error;
  String _recognizedPreview = '';
  bool _busy = false;
  bool _starting = false;
  bool _switching = false;
  bool _disposed = false;
  int _cameraGeneration = 0;
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
    _cameraGeneration++;
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
      _backCameras = cameras
          .where((camera) => camera.lensDirection == CameraLensDirection.back)
          .toList();
      final closeLens = _backCameras.where(
        (camera) => camera.lensType == CameraLensType.ultraWide,
      );
      // The ultra-wide lens can focus closer than the main lens on supported
      // iPhones. Use it for small expiry stamps, with the main lens as fallback.
      final preferred =
          _selectedCamera ??
          (Platform.isIOS && closeLens.isNotEmpty
              ? closeLens.first
              : (_backCameras.isEmpty ? cameras.first : _backCameras.first));
      final alternatives = [
        preferred,
        ..._backCameras.where(
          (camera) =>
              camera.name != preferred.name &&
              camera.lensType == CameraLensType.wide,
        ),
        ..._backCameras.where(
          (camera) =>
              camera.name != preferred.name &&
              camera.lensType != CameraLensType.wide,
        ),
      ];
      CameraController? controller;
      CameraDescription? description;
      for (final candidate in alternatives) {
        final attempt = CameraController(
          candidate,
          ResolutionPreset.veryHigh,
          enableAudio: false,
          imageFormatGroup: Platform.isAndroid
              ? ImageFormatGroup.nv21
              : ImageFormatGroup.bgra8888,
        );
        try {
          await attempt.initialize();
          controller = attempt;
          description = candidate;
          break;
        } catch (_) {
          await attempt.dispose();
        }
      }
      if (controller == null || description == null) {
        throw CameraException(
          'no_supported_camera',
          'No supported back camera',
        );
      }
      if (_disposed ||
          !mounted ||
          WidgetsBinding.instance.lifecycleState == AppLifecycleState.paused ||
          WidgetsBinding.instance.lifecycleState ==
              AppLifecycleState.inactive) {
        await controller.dispose();
        return;
      }
      _description = description;
      _selectedCamera = description;
      _camera = controller;
      setState(() => _error = null);
      // Framing at 2x lets the user hold a small label farther from the lens,
      // where autofocus has a better chance of resolving it.
      await _setZoom(2);
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
      if (camera.value.focusPointSupported) {
        await camera.setFocusPoint(point);
      }
    } on CameraException {
      // Keep the camera running if point autofocus is unavailable.
    }
    try {
      if (camera.value.exposurePointSupported) {
        await camera.setExposurePoint(point);
      }
    } on CameraException {
      // Exposure metering at the center is optional.
    }
  }

  Future<void> _switchLens(CameraDescription description) async {
    if (_switching || _starting || _description?.name == description.name)
      return;
    _switching = true;
    _selectedCamera = description;
    try {
      await _release();
      if (mounted && !_disposed) {
        setState(() {
          _recognizedPreview = '';
          _error = null;
          _zoom = 1;
          _lastFrame = null;
        });
        await _start();
      }
    } finally {
      _switching = false;
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
    final cropped = ExpiryFrameCrop.crop(
      bytes: plane.bytes,
      width: image.width,
      height: image.height,
      bytesPerRow: plane.bytesPerRow,
      bgra: Platform.isIOS,
      quarterTurn:
          image.width > image.height &&
          (camera.value.deviceOrientation == DeviceOrientation.portraitUp ||
              camera.value.deviceOrientation == DeviceOrientation.portraitDown),
    );
    if (cropped == null) return null;
    return InputImage.fromBytes(
      bytes: cropped.bytes,
      metadata: InputImageMetadata(
        size: Size(cropped.width.toDouble(), cropped.height.toDouble()),
        rotation: imageRotation,
        format: format,
        bytesPerRow: cropped.bytesPerRow,
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
            now.difference(_lastFrame!).inMilliseconds < 900)) {
      return;
    }
    final input = _input(frame);
    if (input == null) {
      if (mounted && _error == null) {
        setState(
          () => _error = 'فۆرماتی وێنەی کامێرا بۆ خوێندنەوە بەردەست نییە.',
        );
      }
      return;
    }
    _busy = true;
    _lastFrame = now;
    unawaited(_recognize(input, _cameraGeneration));
  }

  Future<void> _recognize(InputImage input, int generation) async {
    try {
      final text = await _recognizer.processImage(input);
      if (generation != _cameraGeneration) return;
      if (mounted && !_disposed) {
        final preview = text.text.replaceAll(RegExp(r'\s+'), ' ').trim();
        if (preview != _recognizedPreview) {
          setState(() => _recognizedPreview = preview);
        }
      }
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
      _recognizedPreview = '';
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
                              ExpiryFrameCrop.left,
                              ExpiryFrameCrop.right,
                            ),
                            (tap.localPosition.dy / constraints.maxHeight)
                                .clamp(
                                  ExpiryFrameCrop.top,
                                  ExpiryFrameCrop.bottom,
                                ),
                          ),
                        ),
                      ),
                      child: Stack(
                        children: [
                          Positioned.fill(child: CameraPreview(camera)),
                          const Positioned.fill(
                            child: IgnorePointer(
                              child: CustomPaint(painter: _DateGuidePainter()),
                            ),
                          ),
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
                    'تەنها بەرواری E یان EXP بخەرە ناو چوارچێوە. ئەگەر تارە، کاڵاکە کەمێک دوورتر بگرە و لەسەر بەروارەکە تێپ بکە. پێش پاشەکەوتکردن پشتڕاستی بکەرەوە.',
                  ),
                  if (_candidates.isEmpty &&
                      _backCameras.any(
                        (lens) => lens.lensType == CameraLensType.ultraWide,
                      ) &&
                      _backCameras.any(
                        (lens) => lens.lensType == CameraLensType.wide,
                      ))
                    Wrap(
                      spacing: 8,
                      children: [
                        for (final lens in _backCameras.where(
                          (lens) =>
                              lens.lensType == CameraLensType.ultraWide ||
                              lens.lensType == CameraLensType.wide,
                        ))
                          ChoiceChip(
                            label: Text(
                              lens.lensType == CameraLensType.ultraWide
                                  ? 'نزیک · ماکرۆ'
                                  : 'ئاسایی',
                            ),
                            selected: _description?.name == lens.name,
                            onSelected: (_) => unawaited(_switchLens(lens)),
                          ),
                      ],
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
                  if (_candidates.isEmpty && _recognizedPreview.isNotEmpty)
                    Text(
                      'دەقی ناو چوارچێوە: $_recognizedPreview',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  if (_candidates.isEmpty && _error != null)
                    Text(_error!, style: const TextStyle(color: Colors.orange)),
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

class _DateGuidePainter extends CustomPainter {
  const _DateGuidePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final frame = Rect.fromLTRB(
      size.width * ExpiryFrameCrop.left,
      size.height * ExpiryFrameCrop.top,
      size.width * ExpiryFrameCrop.right,
      size.height * ExpiryFrameCrop.bottom,
    );
    final shade = Paint()..color = const Color(0x88000000);
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, frame.top), shade);
    canvas.drawRect(
      Rect.fromLTRB(0, frame.bottom, size.width, size.height),
      shade,
    );
    canvas.drawRect(
      Rect.fromLTRB(0, frame.top, frame.left, frame.bottom),
      shade,
    );
    canvas.drawRect(
      Rect.fromLTRB(frame.right, frame.top, size.width, frame.bottom),
      shade,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(frame, const Radius.circular(12)),
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
  }

  @override
  bool shouldRepaint(covariant _DateGuidePainter oldDelegate) => false;
}
