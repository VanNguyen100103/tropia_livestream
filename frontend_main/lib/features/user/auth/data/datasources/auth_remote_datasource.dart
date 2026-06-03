import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import '../models/auth_model.dart';

abstract class AuthRemoteDataSource {
  Future<AuthModel?> login(String username, String password);

  // Thêm hàm register
  Future<AuthModel?> register({
    required String username,
    required String fullName,
    required String phone,
    required String password,
    required String email,
  });
}

class AuthRemoteDataSourceImpl implements AuthRemoteDataSource {
  final Dio client;

  AuthRemoteDataSourceImpl({required this.client});

  @override
  Future<AuthModel?> login(String username, String password) async {
    try {
      final response = await client.post(
        "login",
        data: {
          "username": username,
          "password": password,
        },
      );

      if (response.statusCode == 200 && response.data['Result'] == true) {
        final data = response.data['data'];
        return AuthModel.fromJson(data);
      }
      return null;
    } catch (e) {
      debugPrint("Lỗi đăng nhập: $e");
      throw Exception("Đăng nhập thất bại: ${e.toString()}");
    }
  }

  // Triển khai hàm register
  @override
  Future<AuthModel?> register({
    required String username,
    required String fullName,
    required String phone,
    required String password,
    required String email,
  }) async {
    try {
      final response = await client.post(
        "register", // Endpoint
        data: {
          "username": username,
          "full_name": fullName, // Map đúng key API yêu cầu
          "so_dien_thoai": phone, // Map đúng key API yêu cầu
          "password": password,
          "email": email,
        },
      );

      // Kiểm tra thành công
      if (response.statusCode == 200 && response.data['Result'] == true) {
        final data = response.data['data'];
        return AuthModel.fromJson(data);
      }

      // Nếu API trả về Result: false hoặc lỗi khác
      // Bạn có thể throw exception để UI bắt lỗi cụ thể
      if (response.data['StatusMess'] != null) {
         throw Exception(response.data['StatusMess']);
      }
      
      return null;
    } catch (e) {
      debugPrint("Lỗi đăng ký: $e");
      rethrow; // Ném lỗi ra ngoài để tầng Repository/Bloc xử lý
    }
  }
}