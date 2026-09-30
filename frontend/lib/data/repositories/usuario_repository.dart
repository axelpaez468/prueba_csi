import '../../core/network/api_client.dart';
import '../models/usuario.dart';

/// Administración de usuarios (la API la restringe a ADMIN).
class UsuarioRepository {
  UsuarioRepository(this._api);

  final ApiClient _api;

  static const _base = '/api/admin/usuarios';

  Future<List<Usuario>> listar({String? buscar}) async {
    final q = (buscar == null || buscar.trim().isEmpty) ? '' : '?buscar=${Uri.encodeQueryComponent(buscar.trim())}';
    final json = await _api.get('$_base$q') as List;
    return json.map((e) => Usuario.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// Crea el usuario y el servidor le envía la invitación para definir su contraseña.
  Future<Usuario> crear(DatosUsuario datos) async =>
      Usuario.fromJson(await _api.post(_base, datos.toJson()) as Map<String, dynamic>);

  Future<Usuario> editar(int id, DatosUsuario datos) async =>
      Usuario.fromJson(await _api.put('$_base/$id', datos.toJson()) as Map<String, dynamic>);

  Future<Usuario> cambiarEstado(int id, {required bool activo}) async => Usuario.fromJson(
      await _api.post('$_base/$id/${activo ? 'activar' : 'desactivar'}', const <String, dynamic>{})
          as Map<String, dynamic>);

  Future<String> reenviarInvitacion(int id) async =>
      ((await _api.post('$_base/$id/invitacion', const <String, dynamic>{})) as Map<String, dynamic>)['mensaje']
          as String;

  Future<void> eliminar(int id) => _api.delete('$_base/$id');
}
