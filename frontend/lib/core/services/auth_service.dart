// =============================================================================
// auth_service.dart
// Quản lý JWT từ Node.js backend – thay thế Supabase Auth.
// Realtime subscription vẫn dùng Supabase client (anon key), chỉ auth dùng Node JWT.
// =============================================================================

import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:tropia/core/config/app_config.dart';
import 'package:tropia/core/utils/logger.dart';

const _tag = 'AuthService';
const _kAccessToken  = 'auth_access_token';
const _kRefreshToken = 'auth_refresh_token';
const _kUserId       = 'auth_user_id';
const _kUserRole     = 'auth_user_role';
const _kUserName     = 'auth_user_name';
const _kUserEmail    = 'auth_user_email';

class AuthUser {
  final String id;
  final String email;
  final String name;
  final String role; // 'buyer' | 'seller' | 'admin'
  final String? avatarUrl;

  const AuthUser({
    required this.id,
    required this.email,
    required this.name,
    required this.role,
    this.avatarUrl,
  });

  bool get isSeller => role == 'seller' || role == 'admin';
}

class AuthService extends ChangeNotifier {
  AuthService._();
  static final instance = AuthService._();

  final _dio = Dio(BaseOptions(baseUrl: AppConfig.backendUrl));

  AuthUser? _user;
  String?   _accessToken;
  String?   _refreshToken;

  AuthUser? get currentUser    => _user;
  String?   get accessToken    => _accessToken;
  bool      get isSignedIn     => _user != null && _accessToken != null;
  String    get currentUserId  => _user?.id ?? 'anon_${DateTime.now().millisecondsSinceEpoch}';

  // ── Khởi tạo – đọc token lưu trên máy ──────────────────────────────────────

  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    _accessToken  = prefs.getString(_kAccessToken);
    _refreshToken = prefs.getString(_kRefreshToken);

    if (_accessToken != null) {
      final id    = prefs.getString(_kUserId)    ?? '';
      final role  = prefs.getString(_kUserRole)  ?? 'buyer';
      final name  = prefs.getString(_kUserName)  ?? '';
      final email = prefs.getString(_kUserEmail) ?? '';
      if (id.isNotEmpty) {
        _user = AuthUser(id: id, email: email, name: name, role: role);
      }
    }

    // Luôn refresh token khi khởi động để đảm bảo access token còn hạn
    if (_refreshToken != null) {
      await _tryRefresh();
    }

    // Đồng bộ user data mới nhất từ server
    if (_accessToken != null) {
      await _fetchMe();
    }

    notifyListeners();
    AppLogger.logInfo(_tag, 'Initialized – signed in: $isSignedIn');
  }

  // ── Register ────────────────────────────────────────────────────────────────

  Future<void> register({
    required String email,
    required String password,
    required String name,
    String role = 'buyer',
    String? phone,
    String? shopName,
  }) async {
    final body = <String, dynamic>{
      'email':    email,
      'password': password,
      'fullName': name,
      'role':     role,
    };
    if (phone != null) body['phone'] = phone;
    if (shopName != null) body['shopName'] = shopName;
    final res = await _dio.post('/api/auth/register', data: body);
    // Register không tự đăng nhập, gọi login sau
    AppLogger.logInfo(_tag, 'Registered: ${res.data['user']['email']}');
  }

  // ── Login ───────────────────────────────────────────────────────────────────

  Future<void> login({required String email, required String password}) async {
    final res = await _dio.post('/api/auth/login', data: {
      'email':    email,
      'password': password,
    });

    final data = res.data as Map<String, dynamic>;
    await _saveSession(
      accessToken:  data['accessToken'] as String,
      refreshToken: data['refreshToken'] as String?,
      userMap:      data['user'] as Map<String, dynamic>,
    );
    AppLogger.logInfo(_tag, 'Logged in: ${_user?.email}');
    notifyListeners();
  }

  // ── Google OAuth ────────────────────────────────────────────────────────────

  /// Mở browser để đăng nhập Google.
  /// Sau khi Google redirect về deep link tropia://auth/callback?token=...&refresh=...
  /// gọi [handleGoogleCallback] để lưu session.
  Future<void> loginWithGoogle() async {
    final url = Uri.parse('${AppConfig.backendUrl}/api/auth/google');
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      throw Exception('Không thể mở trình duyệt để đăng nhập Google');
    }
    AppLogger.logInfo(_tag, 'Opened Google OAuth browser');
  }

  /// Gọi sau khi app nhận deep link từ Google OAuth callback.
  /// [uri] = tropia://auth/callback?code=OTC  (one-time code, không có token)
  /// Đổi OTC lấy JWT qua GET /api/auth/google/exchange
  Future<bool> handleGoogleCallback(Uri uri) async {
    final code  = uri.queryParameters['code'];
    final error = uri.queryParameters['error'];

    if (error != null) {
      AppLogger.logError(_tag, 'Google OAuth error: $error', null, null);
      return false;
    }
    if (code == null) return false;

    try {
      // Đổi one-time code lấy JWT (token không bao giờ xuất hiện trong URL)
      final res = await _dio.get('/api/auth/google/exchange', queryParameters: {'code': code});
      final data = res.data as Map<String, dynamic>;

      final accessToken = data['accessToken'] as String;

      // Decode JWT payload để lấy user info
      final parts   = accessToken.split('.');
      final payload = String.fromCharCodes(
        base64Url.decode(base64Url.normalize(parts[1])),
      );
      final map = _jsonDecode(payload);

      await _saveSession(
        accessToken:  accessToken,
        refreshToken: null, // refresh token đã set trong httpOnly cookie bởi server
        userMap: {
          'id':        map['id']       ?? '',
          'email':     map['email']    ?? '',
          'name':      map['fullName'] ?? map['name'] ?? '',
          'role':      map['role']     ?? 'buyer',
          'avatarUrl': map['avatarUrl'],
        },
      );
      AppLogger.logInfo(_tag, 'Google OAuth success: ${_user?.email}');
      notifyListeners();
      return true;
    } catch (e) {
      AppLogger.logError(_tag, 'handleGoogleCallback exchange error', e, null);
      return false;
    }
  }

  // ── Fetch current user from server ──────────────────────────────────────────

  Future<void> _fetchMe() async {
    try {
      final res  = await _authorizedDio().get('/api/auth/me');
      final data = res.data as Map<String, dynamic>;
      _user = AuthUser(
        id:        data['id']        as String,
        email:     data['email']     as String,
        name:      data['name']      as String,
        role:      data['role']      as String,
        avatarUrl: data['avatarUrl'] as String?,
      );
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kUserId,    _user!.id);
      await prefs.setString(_kUserRole,  _user!.role);
      await prefs.setString(_kUserName,  _user!.name);
      await prefs.setString(_kUserEmail, _user!.email);
    } catch (e) {
      AppLogger.logError(_tag, 'fetchMe failed – using cached user', e, null);
    }
  }

  // ── Email OTP verification ──────────────────────────────────────────────────

  Future<void> verifyOtp({required String email, required String otp}) async {
    await _dio.post('/api/auth/verify-otp', data: {'email': email, 'otp': otp});
  }

  Future<void> resendVerifyEmail(String email) async {
    await _dio.post('/api/auth/resend-verify-email', data: {'email': email});
  }

  // ── Forgot / reset password ──────────────────────────────────────────────────

  Future<void> forgotPassword(String email) async {
    await _dio.post('/api/auth/forgot-password', data: {'email': email});
  }

  Future<void> resetPassword({required String token, required String newPassword}) async {
    await _dio.post('/api/auth/reset-password', data: {
      'token':       token,
      'newPassword': newPassword,
    });
  }

  /// Làm mới thông tin user từ server (public wrapper quanh _fetchMe).
  Future<void> refreshUser() async {
    await _fetchMe();
    notifyListeners();
  }

  // ── Logout ──────────────────────────────────────────────────────────────────

  Future<void> logout() async {
    try {
      await _authorizedDio().post('/api/auth/logout');
    } catch (_) {}
    await _clearSession();
    AppLogger.logInfo(_tag, 'Logged out');
    notifyListeners();
  }

  // ── Refresh token (tự động khi nhận 401) ────────────────────────────────────

  Future<bool> _tryRefresh() async {
    if (_refreshToken == null) return false;
    try {
      final res = await _dio.post('/api/auth/refresh', data: {
        'refreshToken': _refreshToken,
      });
      final data = res.data as Map<String, dynamic>;
      await _saveSession(
        accessToken:  data['accessToken'] as String,
        refreshToken: data['refreshToken'] as String?,
        userMap:      data['user'] as Map<String, dynamic>,
      );
      return true;
    } catch (e) {
      AppLogger.logError(_tag, 'Token refresh failed', e, null);
      await _clearSession();
      return false;
    }
  }

  // ── Dio instance với Authorization header + auto-retry on 401 ───────────────

  Dio authorizedDio() => _authorizedDio();

  Dio _authorizedDio() {
    final d = Dio(BaseOptions(baseUrl: AppConfig.backendUrl));

    d.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) {
        if (_accessToken != null) {
          options.headers['Authorization'] = 'Bearer $_accessToken';
        }
        handler.next(options);
      },
      onError: (err, handler) async {
        if (err.response?.statusCode == 401 && _refreshToken != null) {
          final ok = await _tryRefresh();
          if (ok) {
            // Retry original request với token mới
            final opts = err.requestOptions;
            opts.headers['Authorization'] = 'Bearer $_accessToken';
            try {
              final retry = await d.fetch(opts);
              return handler.resolve(retry);
            } catch (e) {
              return handler.next(err);
            }
          }
        }
        handler.next(err);
      },
    ));

    return d;
  }

  // ── Persist ─────────────────────────────────────────────────────────────────

  Future<void> _saveSession({
    required String accessToken,
    required String? refreshToken,
    required Map<String, dynamic> userMap,
  }) async {
    _accessToken  = accessToken;
    if (refreshToken != null) _refreshToken = refreshToken;

    _user = AuthUser(
      id:        userMap['id']        as String,
      email:     userMap['email']     as String,
      name:      (userMap['name'] ?? userMap['fullName'] ?? '') as String,
      role:      (userMap['role']     ?? 'buyer') as String,
      avatarUrl: userMap['avatarUrl'] as String?,
    );

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kAccessToken,  _accessToken!);
    if (_refreshToken != null) await prefs.setString(_kRefreshToken, _refreshToken!);
    await prefs.setString(_kUserId,    _user!.id);
    await prefs.setString(_kUserRole,  _user!.role);
    await prefs.setString(_kUserName,  _user!.name);
    await prefs.setString(_kUserEmail, _user!.email);
  }

  Map<String, dynamic> _jsonDecode(String s) =>
      json.decode(s) as Map<String, dynamic>;

  Future<void> _clearSession() async {
    _accessToken  = null;
    _refreshToken = null;
    _user         = null;
    final prefs   = await SharedPreferences.getInstance();
    await prefs.remove(_kAccessToken);
    await prefs.remove(_kRefreshToken);
    await prefs.remove(_kUserId);
    await prefs.remove(_kUserRole);
    await prefs.remove(_kUserName);
    await prefs.remove(_kUserEmail);
  }
}
