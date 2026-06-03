import '../datasources/auth_remote_datasource.dart';
import '../models/auth_model.dart';

class AuthRepository {
  final AuthRemoteDataSource remoteDataSource;

  AuthRepository({required this.remoteDataSource});

  Future<AuthModel?> login(String username, String password) async {
    return await remoteDataSource.login(username, password);
  }

  // Thêm hàm register để gọi xuống datasource
  Future<AuthModel?> register({
    required String username,
    required String fullName,
    required String phone,
    required String password,
    required String email,
  }) async {
    return await remoteDataSource.register(
      username: username,
      fullName: fullName,
      phone: phone,
      password: password,
      email: email,
    );
  }
}