import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

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
  final Map<DateTime, int> _dateObservations = {};
  int _framesWithDates = 0;
  String? _error;
  String _recognizedPreview = '';
  String? _photoPath;
  String? _printedDateKind;
  String? _photoScopeMessage;
  bool _monthYearOnly = false;
  bool _capturing = false;
  bool _busy = false;
  bool _starting = false;
  bool _switching = false;
  bool _disposed = false;
  bool _torchOn = false;
  int _emptyScans = 0;
  int _cameraGeneration = 0;
  DateTime? _lastFrame;
  DateTime? _lastAutoRefocus;
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
        _candidates.isEmpty &&
        _photoPath == null) {
      unawaited(_start());
    }
  }

  Future<void> _release() async {
    _cameraGeneration++;
    final camera = _camera;
    _camera = null;
    _torchOn = false;
    _emptyScans = 0;
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
    if (_switching || _starting || _description?.name == description.name) {
      return;
    }
    _switching = true;
    _selectedCamera = description;
    try {
      await _release();
      if (mounted && !_disposed) {
        setState(() {
          _recognizedPreview = '';
          _dateObservations.clear();
          _framesWithDates = 0;
          _error = null;
          _zoom = 1;
          _lastFrame = null;
          _lastAutoRefocus = null;
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

  Future<void> _toggleTorch() async {
    final camera = _camera;
    if (camera == null || !camera.value.isInitialized) return;
    final enabled = !_torchOn;
    try {
      await camera.setFlashMode(enabled ? FlashMode.torch : FlashMode.off);
      if (mounted && identical(_camera, camera)) {
        setState(() => _torchOn = enabled);
      }
    } on CameraException {
      if (mounted) {
        setState(() => _error = 'چرای کامێرا لەم ئامێرەدا بەردەست نییە.');
      }
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
        _capturing ||
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
        if (preview.isEmpty && _candidates.isEmpty) {
          _emptyScans++;
          final now = DateTime.now();
          if (_emptyScans >= 4 &&
              (_lastAutoRefocus == null ||
                  now.difference(_lastAutoRefocus!) >
                      const Duration(seconds: 8))) {
            _lastAutoRefocus = now;
            _emptyScans = 0;
            // Retry the guide center after several unreadable frames, without
            // repeatedly interrupting continuous autofocus while it settles.
            await _focus(const Offset(0.5, 0.5));
            if (generation != _cameraGeneration) return;
          }
        } else {
          _emptyScans = 0;
        }
      }
      final dates = ExpiryDateParser.candidates(text.text);
      if (dates.isNotEmpty && mounted && !_disposed) {
        _framesWithDates++;
        for (final date in dates.toSet()) {
          _dateObservations.update(
            date,
            (count) => count + 1,
            ifAbsent: () => 1,
          );
        }
        final ranked = _dateObservations.keys.toList()
          ..sort((a, b) {
            final byVotes = _dateObservations[b]!.compareTo(
              _dateObservations[a]!,
            );
            return byVotes == 0 ? a.compareTo(b) : byVotes;
          });
        // When OCR alternates between two years for the same day/month,
        // collect more frames and show both to the user before saving.
        final conflictingYears = ranked.any(
          (first) => ranked.any(
            (second) =>
                first.year != second.year &&
                first.month == second.month &&
                first.day == second.day,
          ),
        );
        final ready =
            _framesWithDates >= (conflictingYears ? 6 : 3) &&
            (_dateObservations[ranked.first]! >= 2 || _framesWithDates >= 6);
        if (!ready) return;
        final camera = _camera;
        if (camera != null && camera.value.isStreamingImages) {
          await camera.stopImageStream();
        }
        if (mounted && generation == _cameraGeneration) {
          setState(() => _candidates = ranked.take(4).toList());
        }
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'بەروار نەخوێندرایەوە؛ دووبارە هەوڵ بدە.');
      }
    } finally {
      _busy = false;
    }
  }

  Future<void> _captureDatePhoto() async {
    final camera = _camera;
    if (_capturing ||
        camera == null ||
        !camera.value.isInitialized ||
        _photoPath != null) {
      return;
    }
    setState(() {
      _capturing = true;
      _error = null;
    });
    // Invalidate OCR callbacks from the stream before switching to a JPEG.
    _cameraGeneration++;
    String? originalPath;
    String? cropPath;
    try {
      if (camera.value.isStreamingImages) {
        await camera.stopImageStream();
      }
      // The same recognizer cannot process a stream frame and a photo at once.
      while (_busy && mounted && identical(_camera, camera)) {
        await Future<void>.delayed(const Duration(milliseconds: 80));
      }
      if (!mounted || !identical(_camera, camera)) return;
      final photo = await camera.takePicture();
      originalPath = photo.path;
      File? crop;
      try {
        crop = await _cropDatePhoto(photo.path);
        cropPath = crop.path;
      } catch (_) {
        // The uncropped photo remains available when a device cannot decode
        // the JPEG or allocate the cropped image.
      }
      final croppedText = crop == null
          ? ''
          : (await _recognizer.processImage(
              InputImage.fromFilePath(crop.path),
            )).text;
      final croppedKind = ExpiryDateParser.printedDateKind(croppedText);
      final croppedDates = ExpiryDateParser.candidates(croppedText);
      final preferCrop =
          croppedDates.isNotEmpty &&
          (croppedKind == 'expiry' || croppedKind == 'best_before');
      final fullText = preferCrop
          ? ''
          : (await _recognizer.processImage(
              InputImage.fromFilePath(photo.path),
            )).text;
      final fullKind = ExpiryDateParser.printedDateKind(fullText);
      final fullDates = ExpiryDateParser.candidates(fullText);
      final useCrop =
          preferCrop ||
          (croppedDates.isNotEmpty &&
              fullDates.isEmpty &&
              croppedKind != 'production');
      final recognizedText = useCrop ? croppedText : fullText;
      final selectedPhoto = useCrop && crop != null ? crop.path : photo.path;
      final kind = useCrop ? croppedKind : fullKind;
      final dates = kind == 'production'
          ? <DateTime>[]
          : (useCrop ? croppedDates : fullDates);
      if (selectedPhoto != photo.path) {
        unawaited(_deleteFile(photo.path));
        originalPath = null;
      }
      if (crop != null && selectedPhoto != crop.path) {
        unawaited(_deleteFile(crop.path));
        cropPath = null;
      }
      if (!mounted || !identical(_camera, camera)) {
        unawaited(_deleteFile(selectedPhoto));
        return;
      }
      setState(() {
        _photoPath = selectedPhoto;
        _printedDateKind = kind;
        _monthYearOnly = ExpiryDateParser.isMonthYearOnly(recognizedText);
        _photoScopeMessage = useCrop
            ? 'تەنها ناو چوارچێوەکە سکان کرا.'
            : 'لە ناو چوارچێوە بەرواری پشتڕاستکراو نەدۆزرایەوە؛ تەواوی وێنەکە خوێندرایەوە. بەروارەکە لەسەر پاکەتەکە بپشکنە.';
        _recognizedPreview = recognizedText
            .replaceAll(RegExp(r'\s+'), ' ')
            .trim();
        _candidates = dates.take(4).toList();
        _error = kind == 'production'
            ? 'تەنها بەرواری بەرهەمهێنان دۆزرایەوە؛ وێنەی بەرواری EXP بگرە.'
            : dates.isEmpty
            ? 'بەرواری بەسەرچوون لە وێنەکە نەدۆزرایەوە. وێنەی ڕوونتر بگرە.'
            : null;
      });
      originalPath = null;
      cropPath = null;
    } catch (_) {
      if (originalPath != null) {
        unawaited(_deleteFile(originalPath));
      }
      if (cropPath != null) {
        unawaited(_deleteFile(cropPath));
      }
      if (mounted) {
        setState(
          () => _error =
              'گرتن یان خوێندنەوەی وێنە سەرکەوتوو نەبوو. دووبارە هەوڵ بدە.',
        );
      }
      if (mounted &&
          identical(_camera, camera) &&
          !camera.value.isStreamingImages &&
          _photoPath == null) {
        try {
          await camera.startImageStream(_readFrame);
        } catch (_) {}
      }
    } finally {
      if (mounted) setState(() => _capturing = false);
    }
  }

  Future<File> _cropDatePhoto(String path) async {
    final codec = await ui.instantiateImageCodec(
      await File(path).readAsBytes(),
    );
    late final ui.FrameInfo frame;
    try {
      frame = await codec.getNextFrame();
    } finally {
      codec.dispose();
    }
    final source = frame.image;
    try {
      final wide = source.width > source.height;
      final bounds = wide
          ? ui.Rect.fromLTWH(
              source.width * 0.35,
              source.height * 0.04,
              source.width * 0.30,
              source.height * 0.92,
            )
          : ui.Rect.fromLTWH(
              source.width * 0.04,
              source.height * 0.35,
              source.width * 0.92,
              source.height * 0.30,
            );
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      canvas.drawImageRect(
        source,
        bounds,
        ui.Rect.fromLTWH(0, 0, bounds.width, bounds.height),
        ui.Paint(),
      );
      final picture = recorder.endRecording();
      final image = await picture.toImage(
        bounds.width.round(),
        bounds.height.round(),
      );
      picture.dispose();
      try {
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        if (bytes == null) throw StateError('Could not encode date crop');
        final file = File(
          '${Directory.systemTemp.path}/zhirox_date_${DateTime.now().microsecondsSinceEpoch}.png',
        );
        await file.writeAsBytes(bytes.buffer.asUint8List(), flush: true);
        return file;
      } finally {
        image.dispose();
      }
    } finally {
      source.dispose();
    }
  }

  Future<void> _deleteFile(String path) async {
    try {
      await File(path).delete();
    } catch (_) {}
  }

  Future<void> _retry() async {
    _cameraGeneration++;
    final oldPhoto = _photoPath;
    setState(() {
      _candidates = const [];
      _photoPath = null;
      _printedDateKind = null;
      _photoScopeMessage = null;
      _monthYearOnly = false;
      _dateObservations.clear();
      _framesWithDates = 0;
      _error = null;
      _recognizedPreview = '';
    });
    if (oldPhoto != null) {
      await _deleteFile(oldPhoto);
    }
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

  Future<void> _correctDate([DateTime? detected]) async {
    final controller = TextEditingController(
      text: detected == null
          ? ''
          : '${detected.day.toString().padLeft(2, '0')}/'
                '${detected.month.toString().padLeft(2, '0')}/'
                '${detected.year}',
    );
    final yearController = TextEditingController();
    String? error;
    try {
      final corrected = await showDialog<DateTime>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (dialogContext, update) => AlertDialog(
            title: const Text('ڕاستکردنەوەی بەروار'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: controller,
                  autofocus: true,
                  keyboardType: TextInputType.datetime,
                  textDirection: TextDirection.ltr,
                  decoration: InputDecoration(
                    labelText: 'ڕۆژ/مانگ/ساڵ',
                    hintText: '28/12/2026',
                    errorText: error,
                  ),
                ),
                if (_photoPath != null)
                  TextField(
                    controller: yearController,
                    keyboardType: TextInputType.number,
                    maxLength: 4,
                    textDirection: TextDirection.ltr,
                    decoration: const InputDecoration(
                      labelText: 'ساڵەکە لەسەر پاکەتەکە دووبارە بنووسە',
                      hintText: '2026',
                    ),
                  ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('پاشگەزبوونەوە'),
              ),
              FilledButton(
                onPressed: () {
                  final date = ExpiryDateParser.enteredDate(controller.text);
                  if (date == null) {
                    update(
                      () =>
                          error = 'بەرواری دروست بە ساڵی چوار ژمارەیی بنووسە.',
                    );
                    return;
                  }
                  if (_photoPath != null &&
                      ExpiryDateParser.enteredDate(
                            '01/01/${yearController.text.trim()}',
                          )?.year !=
                          date.year) {
                    update(
                      () => error =
                          'ساڵەکە لەگەڵ بەرواری سەر پاکەتەکە یەکسان بکە.',
                    );
                    return;
                  }
                  Navigator.of(dialogContext).pop(date);
                },
                child: const Text('پشتڕاستکردنەوە'),
              ),
            ],
          ),
        ),
      );
      if (corrected != null && mounted) {
        final oldPhoto = _photoPath;
        if (oldPhoto != null) {
          unawaited(_deleteFile(oldPhoto));
        }
        Navigator.of(context).pop(corrected);
      }
    } finally {
      controller.dispose();
      yearController.dispose();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_release());
    unawaited(_recognizer.close());
    final photo = _photoPath;
    if (photo != null) {
      unawaited(_deleteFile(photo));
    }
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
            child: _photoPath != null
                ? Center(
                    child: Image.file(File(_photoPath!), fit: BoxFit.contain),
                  )
                : camera != null && camera.value.isInitialized
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
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * 0.52,
              ),
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'بەرواری EXP یان E بخەرە ناو چوارچێوە و وێنەیەکی ڕوون بگرە. لەگەڵ جۆری بەروارەکە و دەقی وێنەکە پێش پاشەکەوتکردن پشتڕاستی بکەرەوە.',
                      ),
                      if (_photoPath == null &&
                          _candidates.isEmpty &&
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
                      if (_photoPath == null && _candidates.isEmpty)
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
                            IconButton(
                              tooltip: _torchOn
                                  ? 'چرای کامێرا بکوژێنەوە'
                                  : 'چرای کامێرا هەڵبکە',
                              onPressed: () => unawaited(_toggleTorch()),
                              icon: Icon(
                                _torchOn ? Icons.flash_on : Icons.flash_off,
                              ),
                            ),
                          ],
                        ),
                      if (_photoPath == null)
                        FilledButton.icon(
                          onPressed: _capturing ? null : _captureDatePhoto,
                          icon: _capturing
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.camera_alt),
                          label: Text(
                            _capturing
                                ? 'وێنەکە دەخوێندرێتەوە…'
                                : 'وێنەی بەروار بگرە و سکان بکە',
                          ),
                        ),
                      if (_photoPath != null)
                        Text(switch (_printedDateKind) {
                          'expiry' => 'جۆری بەروار: بەسەرچوون (EXP)',
                          'best_before' =>
                            'جۆری بەروار: باشترە پێش (Best before)',
                          'production' => 'جۆری بەروار: بەرهەمهێنان (P/MFG)',
                          _ =>
                            'جۆری بەروار: دیار نییە؛ پێش تۆمارکردن لەسەر پاکەتەکە بپشکنە',
                        }),
                      if (_photoScopeMessage != null)
                        Text(
                          _photoScopeMessage!,
                          style: const TextStyle(color: Colors.orange),
                        ),
                      if (_monthYearOnly)
                        const Text(
                          'لەسەر کاڵاکە تەنها مانگ و ساڵ نووسراوە؛ ڕۆژی پێشنیارکراو کۆتا ڕۆژی ئەو مانگەیە.',
                          style: TextStyle(color: Colors.orange),
                        ),
                      if (_recognizedPreview.isNotEmpty)
                        Text(
                          'دەقی خوێندراوە: $_recognizedPreview',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      if (_candidates.length > 1)
                        const Text(
                          'بەروارەکە چەند مانایەکی هەیە؛ ڕۆژ و مانگ و ساڵ لەسەر پاکەتەکە بپشکنە، پاشان پشتڕاستی بکەرەوە.',
                          style: TextStyle(color: Colors.orange),
                        ),
                      if (_candidates.isEmpty && _error != null)
                        Text(
                          _error!,
                          style: const TextStyle(color: Colors.orange),
                        ),
                      if (_candidates.isEmpty)
                        Wrap(
                          children: [
                            TextButton.icon(
                              onPressed: _retry,
                              icon: const Icon(Icons.refresh),
                              label: const Text('دووبارە هەوڵ بدە'),
                            ),
                            TextButton.icon(
                              onPressed: _printedDateKind == 'production'
                                  ? null
                                  : () => unawaited(_correctDate()),
                              icon: const Icon(Icons.edit_calendar),
                              label: const Text('بەروار بە دەست بنووسە'),
                            ),
                          ],
                        )
                      else ...[
                        for (final date in _candidates.take(4))
                          ListTile(
                            leading: const Icon(Icons.event_available),
                            title: Text(
                              '${date.year}/${date.month}/${date.day}',
                            ),
                            subtitle: const Text(
                              'ساڵەکە بپشکنە و پشتڕاستی بکەرەوە',
                            ),
                            trailing: const Icon(Icons.edit_calendar),
                            onTap: () => unawaited(_correctDate(date)),
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
