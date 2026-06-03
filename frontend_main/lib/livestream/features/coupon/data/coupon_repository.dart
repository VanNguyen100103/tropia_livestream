import 'package:tropia_mobile_app_android/livestream/core/services/auth_service.dart';

class CouponModel {
  final String id;
  final String code;
  final String discountType; // 'percent' | 'fixed'
  final double discountValue;
  final int minOrderValue;
  final double? maxDiscount;
  final DateTime expiresAt;

  const CouponModel({
    required this.id,
    required this.code,
    required this.discountType,
    required this.discountValue,
    required this.minOrderValue,
    this.maxDiscount,
    required this.expiresAt,
  });

  factory CouponModel.fromJson(Map<String, dynamic> j) => CouponModel(
        id:            j['id']             as String,
        code:          j['code']           as String,
        discountType:  j['discount_type']  as String,
        discountValue: (j['discount_value'] as num).toDouble(),
        minOrderValue: (j['min_order_value'] as num? ?? 0).toInt(),
        maxDiscount:   (j['max_discount']   as num?)?.toDouble(),
        expiresAt:     DateTime.parse(j['expires_at'] as String),
      );

  /// Tính tiền giảm thực tế cho orderTotal (đơn vị đồng)
  int calcDiscount(int orderTotal) {
    double amount = discountType == 'percent'
        ? orderTotal * discountValue / 100
        : discountValue;
    if (maxDiscount != null && amount > maxDiscount!) {
      amount = maxDiscount!;
    }
    return amount.round().clamp(0, orderTotal);
  }

  /// Label hiển thị: "Giảm 20%" hoặc "Giảm 50.000đ"
  String get discountLabel => discountType == 'percent'
      ? 'Giảm ${discountValue.toInt()}%'
      : 'Giảm ${_fmt(discountValue.toInt())}';

  String _fmt(int n) {
    final s = n.toString();
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write('.');
      buf.write(s[i]);
    }
    return '${buf}đ';
  }
}

class CouponRepository {
  CouponRepository._();
  static final instance = CouponRepository._();

  get _dio => AuthService.instance.authorizedDio();

  /// POST /api/coupons/validate
  Future<Map<String, dynamic>> validate({
    required String code,
    required int orderTotal,
  }) async {
    final res = await _dio.post('/api/coupons/validate', data: {
      'code':       code,
      'orderTotal': orderTotal,
    });
    return res.data as Map<String, dynamic>;
  }

  /// GET /api/coupons/available — platform coupons (no session_id)
  Future<List<CouponModel>> getAvailable() async {
    final res = await _dio.get('/api/coupons/available');
    final list = (res.data as Map<String, dynamic>)['data'] as List? ?? [];
    return list.map((e) => CouponModel.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// GET /api/coupons/shop/:shopId — coupons from that shop's live sessions
  Future<List<CouponModel>> getShopCoupons(String shopId) async {
    final res = await _dio.get('/api/coupons/shop/$shopId');
    final list = (res.data as Map<String, dynamic>)['data'] as List? ?? [];
    return list.map((e) => CouponModel.fromJson(e as Map<String, dynamic>)).toList();
  }
}
