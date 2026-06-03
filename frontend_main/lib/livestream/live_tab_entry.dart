// =============================================================================
// live_tab_entry.dart — integration entry point for the Live module
// =============================================================================
// Bridges the ported standalone livestream app (lib/livestream/**) into the
// main Tropia app's dashboard bottom nav.
//
// The Live tab is an immersive, self-contained experience that talks to the
// Go livestream backend (AppConfig.backendUrl, default :3000) with its OWN
// auth (flutter_secure_storage JWT) — separate from the main app's auth. It
// therefore owns its own Provider tree (UserProvider / CartProvider /
// LiveProvider / ShopProvider) instead of relying on the host app's state.
//
// Mirrors the provider wiring + AuthService bootstrap that the standalone
// app does in its own main.dart, scoped to just the Live tab subtree.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:tropia_mobile_app_android/livestream/core/services/auth_service.dart';
import 'package:tropia_mobile_app_android/livestream/core/utils/logger.dart';
import 'package:tropia_mobile_app_android/livestream/features/cart/providers/cart_provider.dart';
import 'package:tropia_mobile_app_android/livestream/features/live/providers/live_provider.dart';
import 'package:tropia_mobile_app_android/livestream/features/live/screens/live_tab_screen.dart';
import 'package:tropia_mobile_app_android/livestream/features/shop/providers/shop_provider.dart';
import 'package:tropia_mobile_app_android/livestream/features/user/providers/user_provider.dart';

/// Re-exposes the livestream module's Provider tree to a route pushed from
/// inside the Live tab.
///
/// [LiveTabEntry.build] creates the MultiProvider *below* the app's root
/// Navigator, so any screen pushed with `Navigator.of(context).push(...)`
/// lands OUTSIDE that scope and crashes with
/// "Could not find the correct `Provider<LiveProvider>`" the moment it calls
/// Consumer / context.read / Provider.of. Wrapping the pushed screen with
/// this helper re-provides the *same* instances (via `.value`, so they are
/// never disposed when the route pops) and fixes the lookup.
///
/// Reads eagerly from [source] (valid at push time) so the captured
/// instances — not the route's provider-less context — back the new subtree.
Widget liveScope(BuildContext source, Widget child) {
  final user = source.read<UserProvider>();
  final cart = source.read<CartProvider>();
  final live = source.read<LiveProvider>();
  final shop = source.read<ShopProvider>();
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<UserProvider>.value(value: user),
      ChangeNotifierProvider<CartProvider>.value(value: cart),
      ChangeNotifierProvider<LiveProvider>.value(value: live),
      ChangeNotifierProvider<ShopProvider>.value(value: shop),
    ],
    child: child,
  );
}

/// Entry widget mounted by the dashboard for the "Live" bottom-nav tab.
///
/// Owns the livestream module's Provider tree and lazily initialises the
/// livestream [AuthService] (reads any JWT persisted from a previous live
/// session) the first time the tab is opened.
class LiveTabEntry extends StatefulWidget {
  const LiveTabEntry({super.key});

  @override
  State<LiveTabEntry> createState() => _LiveTabEntryState();
}

class _LiveTabEntryState extends State<LiveTabEntry> {
  // Ensures the AppLogger + AuthService bootstrap only runs once per app
  // process, even though this State is recreated each time the user revisits
  // the tab (the dashboard swaps tab bodies rather than using IndexedStack).
  static bool _bootstrapped = false;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    if (_bootstrapped) return;
    _bootstrapped = true;
    AppLogger.init();
    try {
      await AuthService.instance.initialize();
      AppLogger.logInfo(
        'LiveTabEntry',
        'Live AuthService initialized – signed in: ${AuthService.instance.isSignedIn}',
      );
    } catch (e, st) {
      AppLogger.logError('LiveTabEntry', 'Live AuthService init failed', e, st);
    }
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => UserProvider()),
        ChangeNotifierProvider(create: (_) => CartProvider()),
        // LiveProvider depends on CartProvider so live add-to-cart updates the
        // shared cart. ProxyProvider keeps one LiveProvider and re-injects the
        // cart on update (mirrors the standalone app's main.dart wiring).
        ChangeNotifierProxyProvider<CartProvider, LiveProvider>(
          create: (_) => LiveProvider(),
          update: (_, cart, live) => (live ?? LiveProvider())..cartProvider = cart,
        ),
        ChangeNotifierProvider(create: (_) => ShopProvider()),
      ],
      child: const LiveTabScreen(),
    );
  }
}
