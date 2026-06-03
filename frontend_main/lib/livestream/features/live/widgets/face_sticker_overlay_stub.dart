// Web / desktop stub. ML Kit face detection is mobile-only; this file
// lets the conditional import in face_sticker_overlay.dart resolve to a
// no-op so the web bundle compiles without the native plugin.

import 'package:flutter/material.dart';

import 'face_sticker_overlay.dart' show FaceStickerKind;

class FaceStickerOverlayImpl extends StatelessWidget {
  final dynamic cameraController;
  final FaceStickerKind sticker;

  const FaceStickerOverlayImpl({
    super.key,
    required this.cameraController,
    required this.sticker,
  });

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
