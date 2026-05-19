import 'package:flutter_test/flutter_test.dart';
import 'package:tropia/features/user/models/user_model.dart';

void main() {
  // ── UserRole extension ────────────────────────────────────────────────────

  group('UserRole.canHostLive', () {
    test('buyer cannot host live', () {
      expect(UserRole.buyer.canHostLive, isFalse);
    });

    test('seller can host live', () {
      expect(UserRole.seller.canHostLive, isTrue);
    });
  });

  group('UserRole.displayName', () {
    test('buyer displayName is Người mua', () {
      expect(UserRole.buyer.displayName, 'Người mua');
    });

    test('seller displayName is Người bán', () {
      expect(UserRole.seller.displayName, 'Người bán');
    });
  });

  group('UserRole.description', () {
    test('buyer description is non-empty', () {
      expect(UserRole.buyer.description, isNotEmpty);
    });

    test('seller description is non-empty', () {
      expect(UserRole.seller.description, isNotEmpty);
    });
  });

  // ── UserModel constructor ─────────────────────────────────────────────────

  group('UserModel constructor', () {
    test('stores all fields correctly', () {
      const user = UserModel(
        id: 'u-001',
        name: 'Ngân Văn',
        email: 'ngan@tropia.vn',
        avatarUrl: 'https://cdn.tropia.vn/avatar.jpg',
        role: UserRole.buyer,
      );
      expect(user.id, 'u-001');
      expect(user.name, 'Ngân Văn');
      expect(user.email, 'ngan@tropia.vn');
      expect(user.avatarUrl, 'https://cdn.tropia.vn/avatar.jpg');
      expect(user.role, UserRole.buyer);
    });

    test('avatarUrl defaults to null when omitted', () {
      const user = UserModel(
        id: 'u-002',
        name: 'Test',
        email: 'test@tropia.vn',
        role: UserRole.seller,
      );
      expect(user.avatarUrl, isNull);
    });
  });

  // ── UserModel.copyWith ────────────────────────────────────────────────────

  group('UserModel.copyWith', () {
    const original = UserModel(
      id: 'u-001',
      name: 'Ngân',
      email: 'ngan@tropia.vn',
      role: UserRole.buyer,
    );

    test('returns identical values when no args supplied', () {
      final copy = original.copyWith();
      expect(copy.id, original.id);
      expect(copy.name, original.name);
      expect(copy.email, original.email);
      expect(copy.avatarUrl, original.avatarUrl);
      expect(copy.role, original.role);
    });

    test('overrides only supplied fields', () {
      final copy = original.copyWith(role: UserRole.seller, name: 'Admin');
      expect(copy.role, UserRole.seller);
      expect(copy.name, 'Admin');
      // unchanged fields
      expect(copy.id, original.id);
      expect(copy.email, original.email);
    });

    test('does not mutate the original', () {
      original.copyWith(name: 'Changed');
      expect(original.name, 'Ngân');
    });
  });

  // ── UserModel.fromJson ────────────────────────────────────────────────────

  group('UserModel.fromJson', () {
    test('parses all fields from complete json', () {
      final user = UserModel.fromJson({
        'id': 'u-003',
        'name': 'Bách',
        'email': 'bach@tropia.vn',
        'avatar_url': 'https://cdn.tropia.vn/bach.jpg',
        'role': 'buyer',
      });
      expect(user.id, 'u-003');
      expect(user.name, 'Bách');
      expect(user.email, 'bach@tropia.vn');
      expect(user.avatarUrl, 'https://cdn.tropia.vn/bach.jpg');
      expect(user.role, UserRole.buyer);
    });

    test('role "seller" maps to UserRole.seller', () {
      final user = UserModel.fromJson({
        'id': 'u-004',
        'name': 'Seller',
        'email': 's@tropia.vn',
        'role': 'seller',
      });
      expect(user.role, UserRole.seller);
    });

    test('role "admin" maps to UserRole.buyer (only seller gets seller role)', () {
      final user = UserModel.fromJson({
        'id': 'u-005',
        'name': 'Admin',
        'email': 'a@tropia.vn',
        'role': 'admin',
      });
      expect(user.role, UserRole.buyer);
    });

    test('absent role defaults to UserRole.buyer', () {
      final user = UserModel.fromJson({
        'id': 'u-006',
        'name': 'Guest',
        'email': 'g@tropia.vn',
      });
      expect(user.role, UserRole.buyer);
    });

    test('falls back to email when name is null', () {
      final user = UserModel.fromJson({
        'id': 'u-007',
        'email': 'fallback@tropia.vn',
      });
      expect(user.name, 'fallback@tropia.vn');
    });

    test('avatarUrl is null when absent', () {
      final user = UserModel.fromJson({
        'id': 'u-008',
        'name': 'Carol',
        'email': 'carol@tropia.vn',
      });
      expect(user.avatarUrl, isNull);
    });
  });
}
