import 'package:dio/dio.dart';

class UnusedVoucherRepository {
  final Dio client;
  UnusedVoucherRepository({required this.client});

  Future<List<Map<String, dynamic>>> fetchUnusedVouchers({required String authToken, int page = 1, int limit = 10}) async {
    final response = await client.get(
      'http://tropia.thienhaisoft.com/index.php',
      queryParameters: {
        'r': 'api/vouchers',
        'status': 'active',
        'page': page,
        'limit': limit,
      },
      options: Options(headers: {'Authorization': 'Bearer $authToken'}),
    );
    if (response.statusCode == 200 && response.data['Result'] == true) {
      final List items = response.data['data']['items'] ?? [];
      return List<Map<String, dynamic>>.from(items);
    }
    return [];
  }

  Future<Map<String, dynamic>> saveVoucher({
    required String authToken,
    required int userId,
    required String code,
  }) async {
    final response = await client.post(
      'http://tropia.thienhaisoft.com/index.php?r=api/user-vouchers-save&user_id=$userId',
      data: {'code': code},
      options: Options(
        headers: {
          'Authorization': 'Bearer $authToken',
          'Content-Type': 'application/json',
        },
      ),
    );
    return response.data;
  }
}
