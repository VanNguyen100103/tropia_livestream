// lib/core/network/dio_client.dart
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../constants/api_constants.dart'; // Import file chứa BaseURL

class DioClient {
  final Dio _dio;

  DioClient()
    : _dio = Dio(
        BaseOptions(
          // Gọi getter baseUrl từ ApiConstants (đã cấu hình dotenv)
          baseUrl: ApiConstants.baseUrl,
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 10),
          headers: {
            'Content-Type': 'application/json',
            'Accept': 'application/json',
          },
        ),
      ) {
    // Log request/response chỉ khi debug (tránh lộ token/PII ở production)
    if (kDebugMode) {
      _dio.interceptors.add(
        LogInterceptor(requestBody: true, responseBody: false),
      );
    }
  }

  Dio get dio => _dio;
}
