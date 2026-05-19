import 'package:flutter_test/flutter_test.dart';
import 'package:tropia/features/shop/providers/shop_provider.dart';

void main() {
  late ShopProvider provider;

  setUp(() {
    provider = ShopProvider();
  });

  tearDown(() {
    provider.dispose();
  });

  // ── Initial state ─────────────────────────────────────────────────────────

  group('ShopProvider — initial state', () {
    test('myShop is null', () {
      expect(provider.myShop, isNull);
    });

    test('hasShop is false', () {
      expect(provider.hasShop, isFalse);
    });

    test('status is ShopStatus.idle', () {
      expect(provider.status, ShopStatus.idle);
    });

    test('isLoading is false', () {
      expect(provider.isLoading, isFalse);
    });

    test('isSaving is false', () {
      expect(provider.isSaving, isFalse);
    });

    test('error is null', () {
      expect(provider.error, isNull);
    });
  });

  // ── clearError ────────────────────────────────────────────────────────────

  group('ShopProvider — clearError', () {
    test('safe to call when error is already null', () {
      expect(() => provider.clearError(), returnsNormally);
      expect(provider.error, isNull);
    });

    test('notifies listeners on clearError', () {
      var notified = false;
      provider.addListener(() => notified = true);
      provider.clearError();
      expect(notified, isTrue);
    });

    test('status stays idle after clearError', () {
      provider.clearError();
      expect(provider.status, ShopStatus.idle);
    });

    test('hasShop stays false after clearError', () {
      provider.clearError();
      expect(provider.hasShop, isFalse);
    });

    test('isLoading stays false after clearError', () {
      provider.clearError();
      expect(provider.isLoading, isFalse);
    });

    test('isSaving stays false after clearError', () {
      provider.clearError();
      expect(provider.isSaving, isFalse);
    });
  });

  // ── ShopStatus enum ───────────────────────────────────────────────────────

  group('ShopStatus values', () {
    test('idle != loading', () {
      expect(ShopStatus.idle == ShopStatus.loading, isFalse);
    });

    test('idle != saving', () {
      expect(ShopStatus.idle == ShopStatus.saving, isFalse);
    });

    test('idle != error', () {
      expect(ShopStatus.idle == ShopStatus.error, isFalse);
    });

    test('initial isLoading corresponds to loading status', () {
      expect(provider.isLoading, equals(provider.status == ShopStatus.loading));
    });

    test('initial isSaving corresponds to saving status', () {
      expect(provider.isSaving, equals(provider.status == ShopStatus.saving));
    });
  });
}
