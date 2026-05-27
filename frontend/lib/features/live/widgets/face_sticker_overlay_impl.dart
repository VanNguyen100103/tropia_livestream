// Mobile-only face sticker overlay. Hooks the host's existing
// CameraController image stream into Google ML Kit Face Detection and
// draws an emoji glyph on top of the detected face.
//
// Frame throttling: ML Kit on a Snapdragon 4-series phone runs ~80ms
// per frame. The camera streams ~30fps, so we'd back up the queue if we
// processed everything. We skip frames while a previous detect() is in
// flight — at steady state the overlay updates ~5-8× per second, which
// looks smooth enough for a "tai thỏ" gimmick.

import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

import 'face_sticker_overlay.dart' show FaceStickerKind, FaceStickerKindX;

class FaceStickerOverlayImpl extends StatefulWidget {
  final CameraController cameraController;
  final FaceStickerKind sticker;

  const FaceStickerOverlayImpl({
    super.key,
    required this.cameraController,
    required this.sticker,
  });

  @override
  State<FaceStickerOverlayImpl> createState() => _FaceStickerOverlayImplState();
}

class _FaceStickerOverlayImplState extends State<FaceStickerOverlayImpl> {
  final FaceDetector _detector = FaceDetector(
    options: FaceDetectorOptions(
      // Fast mode, no contours/classifications — we just need the
      // bounding box + a couple of landmarks (eyes, nose) for placement.
      performanceMode: FaceDetectorMode.fast,
      enableLandmarks: true,
    ),
  );

  Face? _face;
  Size? _imageSize;
  bool _busy = false;
  bool _streaming = false;

  @override
  void initState() {
    super.initState();
    _startStream();
  }

  @override
  void didUpdateWidget(covariant FaceStickerOverlayImpl oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.cameraController != widget.cameraController) {
      _stopStream();
      _startStream();
    }
  }

  Future<void> _startStream() async {
    if (_streaming) return;
    final ctrl = widget.cameraController;
    if (!ctrl.value.isInitialized || ctrl.value.isStreamingImages) return;
    try {
      await ctrl.startImageStream(_onCameraImage);
      _streaming = true;
    } catch (_) {
      // Camera might already be in use (apivideo took it over once live
      // started). Silently skip — the host sees the unfiltered preview
      // until they tap into a screen that releases the camera.
    }
  }

  Future<void> _stopStream() async {
    if (!_streaming) return;
    _streaming = false;
    try {
      if (widget.cameraController.value.isStreamingImages) {
        await widget.cameraController.stopImageStream();
      }
    } catch (_) {}
  }

  void _onCameraImage(CameraImage image) {
    if (_busy) return;
    _busy = true;
    _detect(image).whenComplete(() => _busy = false);
  }

  int _logCounter = 0;
  Future<void> _detect(CameraImage image) async {
    try {
      final input = _toInputImage(image);
      if (input == null) {
        // Log once per 30 frames so we don't spam — enough to notice if
        // the format mapping is broken without flooding the console.
        if (_logCounter++ % 30 == 0) {
          debugPrint('[FaceStickerOverlay] InputImage null — format=${image.format.raw}');
        }
        return;
      }
      final faces = await _detector.processImage(input);
      if (_logCounter++ % 30 == 0) {
        debugPrint('[FaceStickerOverlay] frame ${image.width}x${image.height} faces=${faces.length}');
      }
      if (!mounted) return;
      setState(() {
        _face = faces.isEmpty ? null : faces.first;
        _imageSize = Size(image.width.toDouble(), image.height.toDouble());
      });
    } catch (e) {
      if (_logCounter++ % 30 == 0) {
        debugPrint('[FaceStickerOverlay] detect error: $e');
      }
    }
  }

  InputImage? _toInputImage(CameraImage image) {
    // Cobble together the byte buffer ML Kit expects. Android uses YUV420
    // (3 planes), iOS uses BGRA (1 plane) — handle both.
    final WriteBuffer buf = WriteBuffer();
    for (final plane in image.planes) {
      buf.putUint8List(plane.bytes);
    }
    final bytes = buf.done().buffer.asUint8List();

    final rotation = _rotationFor(widget.cameraController);
    if (rotation == null) return null;

    final format = InputImageFormatValue.fromRawValue(image.format.raw);
    if (format == null) return null;

    return InputImage.fromBytes(
      bytes: bytes,
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format: format,
        bytesPerRow: image.planes.first.bytesPerRow,
      ),
    );
  }

  InputImageRotation? _rotationFor(CameraController ctrl) {
    if (Platform.isIOS) {
      // iOS image is already in display orientation.
      return InputImageRotation.rotation0deg;
    }
    final sensorOrientation = ctrl.description.sensorOrientation;
    final lookup = {
      0: InputImageRotation.rotation0deg,
      90: InputImageRotation.rotation90deg,
      180: InputImageRotation.rotation180deg,
      270: InputImageRotation.rotation270deg,
    };
    return lookup[sensorOrientation];
  }

  @override
  void dispose() {
    _stopStream();
    _detector.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final face = _face;
    final imgSize = _imageSize;
    if (face == null || imgSize == null) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (ctx, constraints) {
        // The camera frame is rotated 90° for portrait phones (sensor is
        // landscape, screen is portrait) — so the image we got from ML
        // Kit was already rotated to display orientation by the
        // InputImageRotation hint. In portrait we swap w/h so the math
        // matches the preview the user sees.
        final isPortrait = constraints.maxHeight >= constraints.maxWidth;
        final imgW = isPortrait ? imgSize.height : imgSize.width;
        final imgH = isPortrait ? imgSize.width : imgSize.height;
        // CameraPreview parent uses a cover-fit Transform.scale, so the
        // displayed image is the MAX of the two scale factors (one fills
        // width, the other fills height — pick whichever crops less).
        final scaleX = constraints.maxWidth / imgW;
        final scaleY = constraints.maxHeight / imgH;
        final scale = scaleX > scaleY ? scaleX : scaleY;
        final displayW = imgW * scale;
        final displayH = imgH * scale;
        final dx = (constraints.maxWidth - displayW) / 2;
        final dy = (constraints.maxHeight - displayH) / 2;

        // ML Kit returns the bounding box in image coordinates with
        // (0,0) at the top-left of the rotated frame.
        final box = face.boundingBox;
        // Front camera images are mirrored on Android — flip x.
        final isFront = widget.cameraController.description.lensDirection ==
            CameraLensDirection.front;
        final faceLeft = isFront
            ? (imgW - box.right) * scale + dx
            : box.left * scale + dx;
        final faceTop = box.top * scale + dy;
        final faceW = box.width * scale;
        final faceH = box.height * scale;
        final faceCenterX = faceLeft + faceW / 2;

        final glyph = widget.sticker.glyph;
        // Bunny / cat ears + crown sit above the head. Glasses sit on
        // the eyes (mid-face). Empirically tuned offsets.
        final wantTop = widget.sticker != FaceStickerKind.glasses;
        final glyphSize = faceW * 1.2;
        final glyphTop = wantTop
            ? faceTop - faceH * 0.7
            : faceTop + faceH * 0.18;

        return IgnorePointer(
          child: Stack(
            children: [
              Positioned(
                left: faceCenterX - glyphSize / 2,
                top: glyphTop,
                width: glyphSize,
                height: glyphSize,
                child: FittedBox(
                  fit: BoxFit.contain,
                  child: Text(
                    glyph,
                    style: const TextStyle(fontSize: 96),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
