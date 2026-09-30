import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'session.dart';

/// Persiste con flutter_secure_storage la sesión (JWT), el token de "confiar en este dispositivo"
/// y el correo recordado. Nunca se guarda la contraseña.
class TokenStorage {
  TokenStorage([FlutterSecureStorage? storage]) : _storage = storage ?? const FlutterSecureStorage();

  static const _kSesion = 'pedidos.session';
  static const _kDispositivo = 'pedidos.dispositivo';
  static const _kEmail = 'pedidos.email';

  final FlutterSecureStorage _storage;
  Session? _cache;

  Future<void> save(Session session) async {
    _cache = session;
    await _storage.write(key: _kSesion, value: jsonEncode(session.toJson()));
  }

  Future<Session?> read() async {
    if (_cache != null) return _cache;
    final raw = await _storage.read(key: _kSesion);
    if (raw == null) return null;
    try {
      return _cache = Session.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } on Object {
      // Dato corrupto o de una versión anterior: se descarta.
      await clear();
      return null;
    }
  }

  Future<String?> readToken() async => (await read())?.token;

  /// Cierra la sesión. El token de dispositivo y el correo recordado se conservan a propósito.
  Future<void> clear() async {
    _cache = null;
    await _storage.delete(key: _kSesion);
  }

  Future<String?> leerTokenDispositivo() => _storage.read(key: _kDispositivo);

  Future<void> guardarTokenDispositivo(String token) => _storage.write(key: _kDispositivo, value: token);

  Future<String?> leerEmailRecordado() => _storage.read(key: _kEmail);

  Future<void> recordarEmail(String? email) =>
      email == null ? _storage.delete(key: _kEmail) : _storage.write(key: _kEmail, value: email);
}
