// AR sticker overlay on top of CameraPreview — host-only "tai thỏ /
// tai mèo" filter for the live setup screen. Runs Google ML Kit face
// detection on each camera frame and positions emoji-as-glyph stickers
// over the detected head + eyes.
//
// SCOPE NOTE: this only modifies the host's local preview. The RTMP
// frames pushed to SRS by apivideo_live_stream are the raw camera buffer
// — buyers do NOT see the sticker. Composing the filter into the
// encoded stream would need a custom native plugin (Camera2 + OpenGL +
// MediaCodec) which is out of scope for this MVP demo.
//
// Web: import is gated by `dart.library.io` so the ML Kit native plugin
// never gets compiled into the web bundle.

import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform, kIsWeb;
import 'package:flutter/material.dart';

import 'face_sticker_overlay_stub.dart'
    if (dart.library.io) 'face_sticker_overlay_impl.dart' as impl;

enum FaceStickerKind {
  none,
  bunnyEars,
  catEars,
  crown,
  glasses,
}

extension FaceStickerKindX on FaceStickerKind {
  String get label {
    switch (this) {
      case FaceStickerKind.none: return 'Không';
      case FaceStickerKind.bunnyEars: return 'Tai thỏ';
      case FaceStickerKind.catEars: return 'Tai mèo';
      case FaceStickerKind.crown: return 'Vương miện';
      case FaceStickerKind.glasses: return 'Kính';
    }
  }

  /// Emoji glyph drawn on top of the face. Keep them single-codepoint so
  /// the layout math (centering, scale by face width) stays predictable.
  String get glyph {
    switch (this) {
      case FaceStickerKind.none: return '';
      case FaceStickerKind.bunnyEars: return '🐰';
      case FaceStickerKind.catEars: return '🐱';
      case FaceStickerKind.crown: return '👑';
      case FaceStickerKind.glasses: return '🕶️';
    }
  }
}

class FaceStickerOverlay extends StatelessWidget {
  /// The same CameraController already shown on screen by CameraPreview.
  /// We piggyback its image stream so we don't have to open the camera
  /// twice (ML Kit's CameraController.startImageStream is what powers
  /// the face detection).
  final dynamic cameraController; // CameraController; loose-typed so the web stub doesn't need to import package:camera
  final FaceStickerKind sticker;

  const FaceStickerOverlay({
    super.key,
    required this.cameraController,
    required this.sticker,
  });

  @override
  Widget build(BuildContext context) {
    if (sticker == FaceStickerKind.none) return const SizedBox.shrink();
    // Web + desktop: ML Kit native plugin isn't available. Render
    // nothing so the rest of the live screen still builds.
    if (kIsWeb) return const SizedBox.shrink();
    if (defaultTargetPlatform != TargetPlatform.android &&
        defaultTargetPlatform != TargetPlatform.iOS) {
      return const SizedBox.shrink();
    }
    return impl.FaceStickerOverlayImpl(
      cameraController: cameraController,
      sticker: sticker,
    );
  }
}
