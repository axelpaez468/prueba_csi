import '../../core/network/api_client.dart';
import '../../core/security/session.dart';

class AuthRepository {
  AuthRepository(this._api);

  final ApiClient _api;

  /// Las credenciales van en el cuerpo JSON (nunca en la URL, donde quedarían en logs).
  Future<Session> login(String username, String password) async {
    final json = await _api.post(
      '/api/auth/login',
      {'username': username, 'password': password},
      authenticated: false,
    );
    return Session.fromJson(json as Map<String, dynamic>);
  }
}
