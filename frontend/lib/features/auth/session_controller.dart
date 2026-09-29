import 'package:flutter/foundation.dart';

import '../../core/network/api_exception.dart';
import '../../core/security/session.dart';
import '../../core/security/token_storage.dart';
import '../../data/repositories/auth_repository.dart';

enum SessionStatus { restoring, unauthenticated, authenticated }

class SessionController extends ChangeNotifier {
  SessionController(this._auth, this._storage);

  final AuthRepository _auth;
  final TokenStorage _storage;

  SessionStatus _status = SessionStatus.restoring;
  Session? _session;
  bool _loggingIn = false;
  String? _error;

  SessionStatus get status => _status;
  Session? get session => _session;
  bool get loggingIn => _loggingIn;

  /// Mensaje para la pantalla de login (credenciales inválidas, sesión expirada, etc.).
  String? get error => _error;

  Future<void> restore() async {
    final guardada = await _storage.read();
    if (guardada == null || guardada.expirada) {
      await _storage.clear();
      _set(SessionStatus.unauthenticated, null);
    } else {
      _set(SessionStatus.authenticated, guardada);
    }
  }

  Future<void> login(String username, String password) async {
    if (_loggingIn) return;
    _loggingIn = true;
    _error = null;
    notifyListeners();

    try {
      final nueva = await _auth.login(username.trim(), password);
      await _storage.save(nueva);
      _set(SessionStatus.authenticated, nueva);
    } on ApiException catch (e) {
      _error = e.message;
    } finally {
      _loggingIn = false;
      notifyListeners();
    }
  }

  /// [expirada]: se llamó por un 401 del servidor, no por el botón de salir.
  Future<void> logout({bool expirada = false}) async {
    if (_status == SessionStatus.unauthenticated) return;
    await _storage.clear();
    _error = expirada ? 'Su sesión expiró. Inicie sesión de nuevo.' : null;
    _set(SessionStatus.unauthenticated, null);
  }

  void _set(SessionStatus status, Session? session) {
    _status = status;
    _session = session;
    notifyListeners();
  }
}
