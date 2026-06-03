// =============================================================================
// auth_service.dart
// Quản lý JWT từ Node.js backend – thay thế Supabase Auth.
// Realtime subscription vẫn dùng Supabase client (anon key), chỉ auth dùng Node JWT.
// =============================================================================

import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:tropia_mobile_app_android/livestream/core/config/app_config.dart';
import 'package:tropia_mobile_app_android/livestream/core/utils/logger.dart';

const _tag = 'AuthService';
// Token keys live in flutter_secure_storage (Keychain / EncryptedSharedPreferences
// / libsecret). Non-secret display metadata (name, email, role) stays in
// SharedPreferences because it's refreshed from /api/auth/me on every
// startup anyway and isn't security-sensitive on its own.
const _kAccessToken  = 'auth_access_token';
const _kRefreshToken = 'auth_refresh_token';
const _kUserId       = 'auth_user_id';
const _kUserRole     = 'auth_user_role';
const _kUserName     = 'auth_user_name';
const _kUserEmail    = 'auth_user_email';

// Use EncryptedSharedPreferences on Android (API 23+) so values are
// AES-256 wrapped with a key in AndroidKeyStore. iOS / macOS default to
// Keychain with first_unlock accessibility, which matches our re-launch
// flow (tokens needed before the user authenticates).
const _secureStorage = FlutterSecureStorage(
  aOptions: AndroidOptions(encryptedSharedPreferences: true),
  iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
);

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

  final _dio = _buildDio();

  /// Builds a Dio instance with the standard-envelope unwrap interceptor
  /// (see [_envelopeInterceptor]). Used for the unauthenticated endpoints
  /// (login / register / refresh / OAuth exchange).
  static Dio _buildDio() {
    final d = Dio(BaseOptions(baseUrl: AppConfig.backendUrl));
    d.interceptors.add(_envelopeInterceptor());
    return d;
  }

  /// Every backend JSON response is wrapped in the standard envelope
  /// (LIVESTREAM_API.md §1):
  ///   { Result, StatusCode, StatusMess, status, message, data }
  /// This interceptor unwraps successful responses so callers keep reading
  /// `response.data` as the inner payload, and turns `Result == false`
  /// bodies into a DioException carrying the Vietnamese `message` so the
  /// existing try/catch + SnackBar code paths surface it unchanged.
  static Interceptor _envelopeInterceptor() {
    return InterceptorsWrapper(
      onResponse: (response, handler) {
        final body = response.data;
        if (body is Map && body.containsKey('Result') && body.containsKey('data')) {
          if (body['Result'] == false) {
            handler.reject(DioException(
              requestOptions: response.requestOptions,
              response: response,
              type: DioExceptionType.badResponse,
              error: body['message'] ?? body['StatusMess'] ?? 'Đã có lỗi xảy ra',
            ));
            return;
          }
          response.data = body['data'];
        }
        handler.next(response);
      },
    );
  }

  /// Pulls the human-readable message out of a DioException whose response
  /// is an error envelope. Falls back to the exception's own message.
  static String errorMessage(Object e) {
    if (e is DioException) {
      final data = e.response?.data;
      if (data is Map) {
        final m = data['message'] ?? data['StatusMess'] ?? data['error'];
        if (m is String && m.isNotEmpty) return m;
      }
      if (e.error is String && (e.error as String).isNotEmpty) return e.error as String;
    }
    return 'Đã có lỗi xảy ra, vui lòng thử lại';
  }

  AuthUser? _user;
  String?   _accessToken;
  String?   _refreshToken;

  // Holds the PKCE code_verifier between [loginWithGoogle] (which opens
  // the browser) and [handleGoogleCallback] (which spends the OTC). Kept
  // in memory only — if the app is killed mid-flow the user just needs
  // to retry, which is safer than persisting the verifier to disk.
  String? _pendingGoogleVerifier;

  AuthUser? get currentUser    => _user;
  String?   get accessToken    => _accessToken;
  bool      get isSignedIn     => _user != null && _accessToken != null;
  String    get currentUserId  => _user?.id ?? 'anon_${DateTime.now().millisecondsSinceEpoch}';

  // ── Khởi tạo – đọc token lưu trên máy ──────────────────────────────────────

  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();

    _accessToken  = await _secureStorage.read(key: _kAccessToken);
    _refreshToken = await _secureStorage.read(key: _kRefreshToken);

    // One-time migration: older builds stored tokens in SharedPreferences.
    // Move them to secure storage and wipe the plaintext copy. Safe to drop
    // this block once analytics show no users on those builds.
    if (_accessToken == null) {
      final legacyAccess  = prefs.getString(_kAccessToken);
      final legacyRefresh = prefs.getString(_kRefreshToken);
      if (legacyAccess != null) {
        await _secureStorage.write(key: _kAccessToken, value: legacyAccess);
        _accessToken = legacyAccess;
      }
      if (legacyRefresh != null) {
        await _secureStorage.write(key: _kRefreshToken, value: legacyRefresh);
        _refreshToken = legacyRefresh;
      }
      await prefs.remove(_kAccessToken);
      await prefs.remove(_kRefreshToken);
    }

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
    // Go backend uses snake_case keys (see internal/auth/handler.go registerReq).
    final body = <String, dynamic>{
      'email':    email,
      'password': password,
      'name':     name,
      'role':     role,
    };
    if (phone != null) body['phone'] = phone;
    if (shopName != null) body['shop_name'] = shopName;
    final res = await _dio.post('/api/auth/register', data: body);
    // Register không tự đăng nhập, gọi login sau
    AppLogger.logInfo(_tag, 'Registered: ${res.data['user']['email']}');
  }

  // ── Login ───────────────────────────────────────────────────────────────────

  /// Đăng nhập bằng SĐT hoặc email. Backend /api/auth/login nhận `username`
  /// (resolve phone→email) và vẫn trả access_token + refresh_token + user{UUID}.
  Future<void> login({required String username, required String password}) async {
    final res = await _dio.post('/api/auth/login', data: {
      'username': username,
      'password': password,
    });

    final data = res.data as Map<String, dynamic>;
    // Go backend returns snake_case (access_token, refresh_token).
    // Keep camelCase fallbacks for transition / older builds.
    await _saveSession(
      accessToken:  (data['access_token']  ?? data['accessToken'])  as String,
      refreshToken: (data['refresh_token'] ?? data['refreshToken']) as String?,
      userMap:      data['user'] as Map<String, dynamic>,
    );
    AppLogger.logInfo(_tag, 'Logged in: ${_user?.email}');
    notifyListeners();
  }

  // ── Google OAuth ────────────────────────────────────────────────────────────

  /// Mở browser để đăng nhập Google. Sinh PKCE code_verifier rồi gửi
  /// code_challenge (S256) lên backend qua query — nếu một app khác cùng
  /// đăng ký scheme `tropia://` chặn được deep-link, nó vẫn không đổi
  /// được OTC lấy JWT vì thiếu verifier.
  Future<void> loginWithGoogle() async {
    final verifier = _generatePkceVerifier();
    final challenge = _pkceChallenge(verifier);
    _pendingGoogleVerifier = verifier;

    final url = Uri.parse(
      '${AppConfig.backendUrl}/api/auth/google'
      '?code_challenge=$challenge&code_challenge_method=S256',
    );
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      _pendingGoogleVerifier = null;
      throw Exception('Không thể mở trình duyệt để đăng nhập Google');
    }
    AppLogger.logInfo(_tag, 'Opened Google OAuth browser (PKCE)');
  }

  /// RFC 7636 §4.1: code_verifier is 43-128 chars from the unreserved set
  /// [A-Z a-z 0-9 - . _ ~]. We use 64 chars of base64url-encoded random
  /// bytes (no padding) which gives ~384 bits of entropy.
  String _generatePkceVerifier() {
    final rng = Random.secure();
    final bytes = Uint8List(48); // 48 bytes → 64 base64url chars
    for (var i = 0; i < bytes.length; i++) {
      bytes[i] = rng.nextInt(256);
    }
    return base64Url.encode(bytes).replaceAll('=', '');
  }

  String _pkceChallenge(String verifier) {
    final digest = sha256.convert(utf8.encode(verifier));
    return base64Url.encode(digest.bytes).replaceAll('=', '');
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
      // PKCE: gửi kèm verifier để backend verify code_challenge.
      final verifier = _pendingGoogleVerifier;
      _pendingGoogleVerifier = null; // single-use
      final res = await _dio.get('/api/auth/google/exchange', queryParameters: {
        'code': code,
        if (verifier != null) 'code_verifier': verifier,
      });
      final data = res.data as Map<String, dynamic>;

      final accessToken = (data['access_token'] ?? data['accessToken']) as String;

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
      'token':        token,
      'new_password': newPassword,  // Go backend uses snake_case
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
      // Go backend: POST /api/auth/refresh { refresh_token } → { access_token, refresh_token }
      // Refresh response doesn't include user — keep existing _user.
      final res = await _dio.post('/api/auth/refresh', data: {
        'refresh_token': _refreshToken,
      });
      final data = res.data as Map<String, dynamic>;
      await _saveSession(
        accessToken:  (data['access_token']  ?? data['accessToken'])  as String,
        refreshToken: (data['refresh_token'] ?? data['refreshToken']) as String?,
        userMap: (data['user'] as Map<String, dynamic>?) ??
                 (_user != null
                     ? {'id': _user!.id, 'email': _user!.email, 'name': _user!.name, 'role': _user!.role}
                     : <String, dynamic>{}),
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

    // Unwrap the standard envelope first so downstream `onResponse` and
    // callers see the inner payload.
    d.interceptors.add(_envelopeInterceptor());

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

    await _secureStorage.write(key: _kAccessToken, value: _accessToken!);
    if (_refreshToken != null) {
      await _secureStorage.write(key: _kRefreshToken, value: _refreshToken!);
    }

    final prefs = await SharedPreferences.getInstance();
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
    await _secureStorage.delete(key: _kAccessToken);
    await _secureStorage.delete(key: _kRefreshToken);
    final prefs   = await SharedPreferences.getInstance();
    // Defensive: also drop any legacy SharedPreferences token copies that
    // pre-date the secure-storage migration.
    await prefs.remove(_kAccessToken);
    await prefs.remove(_kRefreshToken);
    await prefs.remove(_kUserId);
    await prefs.remove(_kUserRole);
    await prefs.remove(_kUserName);
    await prefs.remove(_kUserEmail);
  }
}
