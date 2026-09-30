import 'package:pedidos_app/core/security/session.dart';
import 'package:pedidos_app/core/security/token_storage.dart';

/// TokenStorage en memoria: en pruebas no existe el plugin de almacenamiento seguro.
class StorageEnMemoria extends TokenStorage {
  StorageEnMemoria([this._session]);

  Session? _session;
  String? tokenDispositivo;
  String? emailRecordado;

  @override
  Future<Session?> read() async => _session;
  @override
  Future<void> save(Session session) async => _session = session;
  @override
  Future<void> clear() async => _session = null;
  @override
  Future<String?> leerTokenDispositivo() async => tokenDispositivo;
  @override
  Future<void> guardarTokenDispositivo(String token) async => tokenDispositivo = token;
  @override
  Future<String?> leerEmailRecordado() async => emailRecordado;
  @override
  Future<void> recordarEmail(String? email) async => emailRecordado = email;
}
