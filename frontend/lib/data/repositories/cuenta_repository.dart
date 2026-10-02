import '../../core/network/api_client.dart';
import '../../core/security/session.dart';
import '../models/seguridad.dart';

/// Seguridad de la cuenta del usuario autenticado.
class CuentaRepository {
  CuentaRepository(this._api);

  final ApiClient _api;

  Future<EstadoSeguridad> estado() async =>
      EstadoSeguridad.fromJson(await _api.get('/api/cuenta/seguridad') as Map<String, dynamic>);

  /// Devuelve una sesión nueva: cambiar la contraseña cierra todas las sesiones, incluida la actual.
  Future<Session> cambiarPassword(String actual, String nueva) async =>
      Session.fromJson(await _api.post('/api/cuenta/password', {'actual': actual, 'nueva': nueva}) as Map<String, dynamic>);

  Future<ConfiguracionTotp> iniciarTotp() async {
    final j = await _api.post('/api/cuenta/2fa/totp', const <String, dynamic>{}) as Map<String, dynamic>;
    return ConfiguracionTotp(secreto: j['secreto'] as String, uri: j['uri'] as String);
  }

  Future<List<String>> confirmarTotp(String codigo) async =>
      _codigos(await _api.post('/api/cuenta/2fa/totp/confirmar', {'codigo': codigo}));

  Future<Session> desactivar(String password) async =>
      Session.fromJson(await _api.post('/api/cuenta/2fa/desactivar', {'password': password}) as Map<String, dynamic>);

  Future<List<String>> regenerarCodigos(String password) async =>
      _codigos(await _api.post('/api/cuenta/2fa/codigos-respaldo', {'password': password}));

  Future<List<RegistroAcceso>> misAccesos() async => _registros(await _api.get('/api/cuenta/accesos'));

  Future<List<RegistroAcceso>> bitacora({String? email}) async {
    final q = (email == null || email.trim().isEmpty) ? '' : '?email=${Uri.encodeQueryComponent(email.trim())}';
    return _registros(await _api.get('/api/admin/bitacora$q'));
  }

  static List<String> _codigos(dynamic json) =>
      ((json as Map<String, dynamic>)['codigosRespaldo'] as List).cast<String>();

  static List<RegistroAcceso> _registros(dynamic json) =>
      (json as List).map((e) => RegistroAcceso.fromJson(e as Map<String, dynamic>)).toList();
}
