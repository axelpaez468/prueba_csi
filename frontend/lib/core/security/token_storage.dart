import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'session.dart';

/// Persiste la sesión (incluido el JWT) con flutter_secure_storage.
class TokenStorage {
  TokenStorage([FlutterSecureStorage? storage]) : _storage = storage ?? const FlutterSecureStorage();

  static const _key = 'pedidos.session';

  final FlutterSecureStorage _storage;
  Session? _cache;

  Future<void> save(Session session) async {
    _cache = session;
    await _storage.write(key: _key, value: jsonEncode(session.toJson()));
  }

  Future<Session?> read() async {
    if (_cache != null) return _cache;
    final raw = await _storage.read(key: _key);
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

  Future<void> clear() async {
    _cache = null;
    await _storage.delete(key: _key);
  }
}
