import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/voucher_model.dart';

class VoucherRepository {
  final Dio client;

  VoucherRepository({required this.client});

  Future<List<VoucherModel>> getUserVouchers(int userId, {String status = 'active'}) async {
    try {
      // 1. Lấy App Token
      final prefs = await SharedPreferences.getInstance();
      final appToken = prefs.getString('app_auth_token') ?? '';

      final options = Options(headers: {"Authorization": "Bearer $appToken"});

      // 2. Gọi API
      final response = await client.get(
        "user-vouchers",
        queryParameters: {
          'user_id': userId,
          'status': status,
        },
        options: options,
      );

      // 3. Parse Data
      if (response.statusCode == 200 && response.data['Result'] == true) {
        final List items = response.data['data']['items'] ?? [];
        return items.map((e) => VoucherModel.fromJson(e)).toList();
      }
      return [];
    } catch (e) {
      debugPrint("Lỗi lấy Voucher: $e");
      return [];
    }
  }
}