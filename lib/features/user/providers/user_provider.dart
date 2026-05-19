import 'package:flutter/foundation.dart';
import 'package:tropia/core/services/auth_service.dart';
import 'package:tropia/core/utils/logger.dart';
import 'package:tropia/features/user/models/user_model.dart';

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
  bool get canHostLive => role.canHostLive;

  void _syncFromAuth() {
    final auth = AuthService.instance.currentUser;
    if (auth == null) {
      _currentUser = null;
    } else {
      _currentUser = UserModel(
        id:        auth.id,
        email:     auth.email,
        name:      auth.name,
        avatarUrl: auth.avatarUrl,
        role:      _roleFrom(auth.role),
      );
    }
    AppLogger.logInfo(_tag, 'Synced from AuthService – signed in: $isSignedIn');
    notifyListeners();
  }

  UserRole _roleFrom(String r) =>
      r == 'seller' || r == 'admin' ? UserRole.seller : UserRole.buyer;

  @override
  void dispose() {
    AuthService.instance.removeListener(_syncFromAuth);
    super.dispose();
  }
}
