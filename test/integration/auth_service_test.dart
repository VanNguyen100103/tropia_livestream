// Integration test for AuthService
// Dùng SharedPreferences mock (flutter_test built-in) để kiểm tra persist/clear session.
// Không gọi HTTP thật — kiểm tra logic session state, token save/load, logout.

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tropia/core/services/auth_service.dart';

void main() {
  // Reset SharedPreferences trước mỗi test
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
  });

  // ── Initial state ─────────────────────────────────────────────────────────

  group('AuthService — initial state (no stored session)', () {
    test('isSignedIn is false before initialize', () {
      expect(AuthService.instance.isSignedIn, isFalse);
    });

    test('currentUser is null before initialize', () {
      expect(AuthService.instance.currentUser, isNull);
    });

    test('accessToken is null before initialize', () {
      expect(AuthService.instance.accessToken, isNull);
    });

    test('currentUserId starts with "anon_"', () {
      expect(AuthService.instance.currentUserId, startsWith('anon_'));
    });
  });

  // ── Session persistence ───────────────────────────────────────────────────

  group('AuthService — session persistence via SharedPreferences', () {
    test('initialize reads nothing when prefs are empty', () async {
      // prefs đã được set empty trong setUp
      // Gọi initialize sẽ không throw
      // (sẽ cố refresh token nhưng _refreshToken == null → skip)
      // Chỉ kiểm tra không crash và state vẫn là unauthenticated
      //
      // Lưu ý: initialize() gọi _tryRefresh() và _fetchMe() qua HTTP.
      // Vì không có token, nó sẽ skip cả hai. Không gọi HTTP.
      await expectLater(AuthService.instance.initialize(), completes);
      expect(AuthService.instance.isSignedIn, isFalse);
    });

    test('initialize restores user from stored prefs', () async {
      // Giả lập đã có token/user trong prefs từ lần đăng nhập trước
      SharedPreferences.setMockInitialValues({
        'auth_access_token': 'stored-token',
        'auth_user_id': 'u-persisted',
        'auth_user_role': 'buyer',
        'auth_user_name': 'Ngân',
        'auth_user_email': 'ngan@tropia.vn',
        // Không set refresh_token → skip _tryRefresh
      });

      // initialize() sẽ đọc prefs → set _user
      // Nhưng sau đó sẽ cố gọi _fetchMe() qua HTTP → sẽ fail silently
      // State trước khi _fetchMe() ghi đè là đã có user
      // Chấp nhận test này dừng ở chỗ: user được set đúng từ prefs
      // Dùng timeout ngắn để tránh chờ network
      try {
        await AuthService.instance.initialize().timeout(
          const Duration(milliseconds: 500),
          onTimeout: () {},
        );
      } catch (_) {}

      // Sau initialize, _user đã được set từ prefs (dù _fetchMe có thể fail)
      // Kiểm tra token được đọc đúng
      expect(AuthService.instance.accessToken, 'stored-token');
    });
  });

  // ── AuthUser ──────────────────────────────────────────────────────────────

  group('AuthUser', () {
    test('isSeller is false for role=buyer', () {
      const user = AuthUser(
          id: 'u1', email: 'a@b.com', name: 'A', role: 'buyer');
      expect(user.isSeller, isFalse);
    });

    test('isSeller is true for role=seller', () {
      const user = AuthUser(
          id: 'u2', email: 'b@b.com', name: 'B', role: 'seller');
      expect(user.isSeller, isTrue);
    });

    test('isSeller is true for role=admin', () {
      const user = AuthUser(
          id: 'u3', email: 'c@b.com', name: 'C', role: 'admin');
      expect(user.isSeller, isTrue);
    });

    test('stores all fields', () {
      const user = AuthUser(
        id: 'u-id',
        email: 'test@tropia.vn',
        name: 'Test User',
        role: 'buyer',
        avatarUrl: 'https://cdn.tropia.vn/av.jpg',
      );
      expect(user.id, 'u-id');
      expect(user.email, 'test@tropia.vn');
      expect(user.name, 'Test User');
      expect(user.role, 'buyer');
      expect(user.avatarUrl, 'https://cdn.tropia.vn/av.jpg');
    });

    test('avatarUrl defaults to null', () {
      const user = AuthUser(id: 'x', email: 'x@x.com', name: 'X', role: 'buyer');
      expect(user.avatarUrl, isNull);
    });
  });

  // ── Logout clears state ───────────────────────────────────────────────────

  group('AuthService — logout clears local state', () {
    test('logout sets isSignedIn to false', () async {
      // Logout gọi POST /api/auth/logout qua HTTP → sẽ fail
      // nhưng try/catch bên trong sẽ bắt, rồi vẫn _clearSession()
      try {
        await AuthService.instance.logout();
      } catch (_) {}
      expect(AuthService.instance.isSignedIn, isFalse);
      expect(AuthService.instance.currentUser, isNull);
      expect(AuthService.instance.accessToken, isNull);
    });
  });
}
