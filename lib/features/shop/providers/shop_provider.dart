import 'package:flutter/foundation.dart';
import 'package:tropia/core/utils/logger.dart';
import 'package:tropia/features/shop/data/shop_repository.dart';
import 'package:tropia/features/shop/models/shop_model.dart';

const _tag = 'ShopProvider';

enum ShopStatus { idle, loading, saving, error }

class ShopProvider extends ChangeNotifier {
  ShopModel? _myShop;
  ShopStatus _status = ShopStatus.idle;
  String? _error;

  ShopModel? get myShop => _myShop;
  ShopStatus get status => _status;
  String? get error => _error;
  bool get hasShop => _myShop != null;
  bool get isLoading => _status == ShopStatus.loading;
  bool get isSaving => _status == ShopStatus.saving;

  Future<void> loadMyShop() async {
    _status = ShopStatus.loading;
    _error = null;
    notifyListeners();
    try {
      _myShop = await ShopRepository.instance.getMyShop();
      _status = ShopStatus.idle;
    } catch (e, st) {
      _error = 'Không thể tải thông tin cửa hàng';
      _status = ShopStatus.error;
      AppLogger.logError(_tag, 'loadMyShop failed', e, st);
    }
    notifyListeners();
  }

  Future<bool> createShop({
    required String name,
    String? description,
  }) async {
    _status = ShopStatus.saving;
    _error = null;
    notifyListeners();
    try {
      _myShop = await ShopRepository.instance.create({
        'name': name,
        if (description != null && description.isNotEmpty) 'description': description,
      });
      _status = ShopStatus.idle;
      AppLogger.logUserEvent(
        action: 'shop_created',
        context: _tag,
        metadata: {'shopId': _myShop!.id, 'name': name},
      );
      notifyListeners();
      return true;
    } catch (e, st) {
      _error = 'Không thể tạo cửa hàng. Thử lại sau.';
      _status = ShopStatus.error;
      AppLogger.logError(_tag, 'createShop failed', e, st);
      notifyListeners();
      return false;
    }
  }

  Future<bool> updateShop({
    String? name,
    String? description,
  }) async {
    if (_myShop == null) return false;
    _status = ShopStatus.saving;
    _error = null;
    notifyListeners();
    try {
      _myShop = await ShopRepository.instance.update(_myShop!.id, {
        if (name != null) 'name': name,
        if (description != null) 'description': description,
      });
      _status = ShopStatus.idle;
      notifyListeners();
      return true;
    } catch (e, st) {
      _error = 'Không thể cập nhật cửa hàng';
      _status = ShopStatus.error;
      AppLogger.logError(_tag, 'updateShop failed', e, st);
      notifyListeners();
      return false;
    }
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }
}
