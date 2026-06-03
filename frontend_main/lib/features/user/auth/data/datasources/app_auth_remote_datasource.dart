import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import '../../../../../core/constants/api_constants.dart';
import '../models/app_token_model.dart';

abstract class AppAuthRemoteDataSource {
  Future<AppTokenModel?> getAuthorToken();
}

class AppAuthRemoteDataSourceImpl implements AppAuthRemoteDataSource {
  final Dio client;

  AppAuthRemoteDataSourceImpl({required this.client});

  @override
  Future<AppTokenModel?> getAuthorToken() async {
    try {
      final domainCode = ApiConstants.imageBaseUrl.replaceAll(
        RegExp(r'/+$'),
        '',
      );
      final headers = {
        'UserLogin': 'TEST_KEY_28075',
        'DomainCode': domainCode,
        'Password':
            'a2efb60d955d83829a6d05fe87b8726316db0cbf9fa743b5dcbb45a21723ae87',
      };

      final response = await client.get(
        "get-author-token",
        options: Options(headers: headers),
      );

      if (response.statusCode == 200 && response.data['Result'] == true) {
        return AppTokenModel.fromJson(response.data);
      }
      return null;
    } catch (e) {
      debugPrint("Lỗi lấy App Token: $e");
      return null;
    }
  }
}
