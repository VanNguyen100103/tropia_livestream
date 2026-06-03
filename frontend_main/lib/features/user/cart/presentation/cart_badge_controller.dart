import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tropia_mobile_app_android/core/network/dio_client.dart';
import 'package:tropia_mobile_app_android/features/user/auth/data/datasources/app_auth_remote_datasource.dart';
import 'package:tropia_mobile_app_android/features/user/auth/data/repositories/app_auth_repository.dart';
import 'package:tropia_mobile_app_android/features/user/cart/data/datasources/cart_remote_datasource.dart';
import 'package:tropia_mobile_app_android/features/user/cart/domain/repositories/cart_repository_impl.dart';

class CartBadgeController {
  CartBadgeController._();

  static final CartBadgeController instance = CartBadgeController._();

  static const String _prefsKey = 'cart_badge_count';

  final ValueNotifier<int> count = ValueNotifier<int>(0);

  Future<void> loadFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getInt(_prefsKey) ?? 0;
    if (stored != count.value) {
      count.value = stored;
    }
  }

  Future<void> setCount(int value) async {
    final safe = value < 0 ? 0 : value;
    if (safe == count.value) return;

    count.value = safe;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_prefsKey, safe);
  }

  Future<void> clear() => setCount(0);

  Future<void> syncFromApi({bool authenticateIfMissingToken = true}) async {
    if (_syncInFlight != null) return _syncInFlight;

    final completer = Completer<void>();
    _syncInFlight = completer.future;

    try {
      final prefs = await SharedPreferences.getInstance();
      final userId = prefs.getInt('user_id') ?? 0;
      if (userId == 0) {
        await clear();
        return;
      }

      final token = prefs.getString('app_auth_token') ?? '';
      if (token.isEmpty && authenticateIfMissingToken) {
        final dio = DioClient().dio;
        final appAuthRepo = AppAuthRepository(
          remoteDataSource: AppAuthRemoteDataSourceImpl(client: dio),
        );
        await appAuthRepo.authenticateApp();
      }

      final dio = DioClient().dio;
      final cartRepo = CartRepositoryImpl(
        remoteDataSource: CartRemoteDataSourceImpl(client: dio),
      );

      final cart = await cartRepo.getCart(userId);
      if (cart == null) return;

      int totalItems = cart.summary.totalItems;
      if (totalItems == 0 && cart.items.isNotEmpty) {
        totalItems = cart.items.fold(0, (sum, item) => sum + item.quantity);
      }

      await setCount(totalItems);
    } catch (_) {
      // Ignore sync errors; badge will update next time.
    } finally {
      completer.complete();
      _syncInFlight = null;
    }
  }

  Future<void>? _syncInFlight;
}
