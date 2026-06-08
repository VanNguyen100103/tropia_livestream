import 'package:flutter/foundation.dart';
import 'package:tropia_mobile_app_android/live_app/core/services/auth_service.dart';
import 'package:tropia_mobile_app_android/live_app/core/utils/logger.dart';
import 'package:tropia_mobile_app_android/live_app/features/live/data/live_repository.dart';
import 'package:tropia_mobile_app_android/live_app/features/user/models/user_model.dart';

const _tag = 'UserProvider';

class UserProvider extends ChangeNotifier {
  UserProvider() {
    _syncFromAuth();
    AuthService.instance.addListener(_syncFromAuth);
  }

  UserModel? _currentUser;

  UserModel? get currentUser => _currentUser;
  bool get isSignedIn => _currentUser != null;
  UserRole get role => _currentUser?.role ?? UserRole.buyer;

  // Quyền phát live lấy từ backend (GET /api/live/can-live) — gồm cả CTV/
  // nhân viên đã được duyệt, không chỉ role seller. null = chưa hỏi xong →
  // tạm fallback theo role để tránh chớp nút.
  bool? _canLiveBackend;
  bool get canHostLive => _canLiveBackend ?? role.canHostLive;

  void _syncFromAuth() {
    final auth = AuthService.instance.currentUser;
    if (auth == null) {
      _currentUser = null;
      _canLiveBackend = null;
    } else {
      _currentUser = UserModel(
        id:        auth.id,
        email:     auth.email,
        name:      auth.name,
        avatarUrl: auth.avatarUrl,
        role:      _roleFrom(auth.role),
      );
      _refreshCanLive();
    }
    AppLogger.logInfo(_tag, 'Synced from AuthService – signed in: $isSignedIn');
    notifyListeners();
  }

  // Hỏi backend quyền live; chỉ cập nhật khi có kết quả rõ ràng (lỗi mạng
  // giữ nguyên fallback role-based).
  Future<void> _refreshCanLive() async {
    final ok = await LiveRepository.instance.canLive();
    if (ok != null && ok != _canLiveBackend) {
      _canLiveBackend = ok;
      notifyListeners();
    }
  }

  UserRole _roleFrom(String r) =>
      r == 'seller' || r == 'admin' ? UserRole.seller : UserRole.buyer;

  @override
  void dispose() {
    AuthService.instance.removeListener(_syncFromAuth);
    super.dispose();
  }
}
