import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:tropia_mobile_app_android/live_app/core/services/auth_service.dart';
import 'package:tropia_mobile_app_android/live_app/core/utils/logger.dart';

class GoogleAuthHandler extends StatefulWidget {
  final Widget child;
  const GoogleAuthHandler({super.key, required this.child});

  @override
  State<GoogleAuthHandler> createState() => _GoogleAuthHandlerState();
}

class _GoogleAuthHandlerState extends State<GoogleAuthHandler> {
  StreamSubscription<Uri>? _sub;
  final _appLinks = AppLinks();

  @override
  void initState() {
    super.initState();
    _sub = _appLinks.uriLinkStream.listen(
      (uri) async {
        if (uri.scheme == 'tropia' && uri.host == 'auth' && uri.path == '/callback') {
          AppLogger.logInfo('GoogleAuthHandler', 'Deep link received: $uri');
          final ok = await AuthService.instance.handleGoogleCallback(uri);
          if (ok && mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Đăng nhập Google thành công!')),
            );
          }
        }
      },
      onError: (e) =>
          AppLogger.logError('GoogleAuthHandler', 'Deep link error', e, null),
    );
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
