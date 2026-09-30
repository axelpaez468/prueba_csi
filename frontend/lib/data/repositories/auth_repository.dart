import '../../core/network/api_client.dart';
import '../../core/security/session.dart';
import '../models/seguridad.dart';

class AuthRepository {
  AuthRepository(this._api);

  final ApiClient _api;

  /// Las credenciales van en el cuerpo JSON (nunca en la URL, donde quedarían en logs).
  Future<ResultadoLogin> login(String email, String password, {String? tokenDispositivo}) async {
    final json = await _api.post(
      '/api/auth/login',
      {'email': email, 'password': password, 'tokenDispositivo': ?tokenDispositivo},
      authenticated: false,
    ) as Map<String, dynamic>;
    return _resultado(json);
  }

  Future<SesionIniciada> verificarSegundoFactor(String desafio, String codigo, {bool confiarDispositivo = false}) async {
    final json = await _api.post(
      '/api/auth/login/verificar',
      {'desafio': desafio, 'codigo': codigo, 'confiarDispositivo': confiarDispositivo},
      authenticated: false,
    ) as Map<String, dynamic>;
    return _resultado(json) as SesionIniciada;
  }

  Future<String> reenviarCodigo(String desafio) async {
    final json = await _api.post('/api/auth/login/reenviar', {'desafio': desafio}, authenticated: false);
    return (json as Map<String, dynamic>)['mensaje'] as String;
  }

  Future<String> solicitarRecuperacion(String email) async {
    final json = await _api.post('/api/auth/recuperar', {'email': email}, authenticated: false);
    return (json as Map<String, dynamic>)['mensaje'] as String;
  }

  Future<String> restablecerPassword(String token, String nuevaPassword) async {
    final json = await _api.post(
      '/api/auth/restablecer',
      {'token': token, 'nuevaPassword': nuevaPassword},
      authenticated: false,
    );
    return (json as Map<String, dynamic>)['mensaje'] as String;
  }

  static ResultadoLogin _resultado(Map<String, dynamic> json) {
    if (json['requiereSegundoFactor'] == true) {
      return SegundoFactorRequerido(
        desafio: json['desafio'] as String,
        metodo: json['metodo'] as String,
        destino: json['destino'] as String?,
      );
    }
    return SesionIniciada(Session.fromJson(json), tokenDispositivo: json['tokenDispositivo'] as String?);
  }
}
