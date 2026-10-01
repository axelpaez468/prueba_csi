import 'package:flutter/foundation.dart';

import '../../core/network/api_client.dart';
import '../../core/network/api_exception.dart';
import '../../core/security/session.dart';
import '../../core/security/token_storage.dart';
import '../../data/models/seguridad.dart';
import '../../data/repositories/auth_repository.dart';

enum SessionStatus { restoring, unauthenticated, segundoFactor, authenticated }

class SessionController extends ChangeNotifier {
  SessionController(this._auth, this._storage);

  final AuthRepository _auth;
  final TokenStorage _storage;

  SessionStatus _status = SessionStatus.restoring;
  Session? _session;
  SegundoFactorRequerido? _desafio;
  String? _emailRecordado;
  List<String>? _codigosRespaldoNuevos;
  bool _procesando = false;
  String? _error;
  String? _aviso;

  SessionStatus get status => _status;
  Session? get session => _session;

  /// Segundo factor pendiente (tras validar la contraseña).
  SegundoFactorRequerido? get desafio => _desafio;

  String? get emailRecordado => _emailRecordado;

  /// Códigos de respaldo recién generados al configurar Google Authenticator en el login:
  /// la app los muestra una sola vez antes de entrar.
  List<String>? get codigosRespaldoNuevos => _codigosRespaldoNuevos;

  void codigosRespaldoGuardados() {
    _codigosRespaldoNuevos = null;
    notifyListeners();
  }
  bool get procesando => _procesando;

  // Alias usado por la pantalla de login.
  bool get loggingIn => _procesando;

  /// Mensaje de error para la pantalla actual (credenciales inválidas, código incorrecto, sesión expirada...).
  String? get error => _error;

  /// Mensaje informativo (p. ej. "enviamos un nuevo código").
  String? get aviso => _aviso;

  Future<void> restore() async {
    _emailRecordado = await _storage.leerEmailRecordado();
    final guardada = await _storage.read();
    if (guardada == null || guardada.expirada) {
      await _storage.clear();
      _set(SessionStatus.unauthenticated, null);
    } else {
      _set(SessionStatus.authenticated, guardada);
    }
  }

  Future<void> login(String email, String password, {bool recordar = false}) async {
    await _ejecutar(() async {
      email = email.trim();
      await _storage.recordarEmail(recordar ? email : null);
      _emailRecordado = recordar ? email : null;

      final resultado = await _auth.login(email, password, tokenDispositivo: await _storage.leerTokenDispositivo());
      switch (resultado) {
        case SesionIniciada():
          await _iniciar(resultado);
        case SegundoFactorRequerido():
          _desafio = resultado;
          _set(SessionStatus.segundoFactor, null);
      }
    });
  }

  Future<void> verificarCodigo(String codigo, {bool confiarDispositivo = false}) async {
    final desafio = _desafio;
    if (desafio == null) return;
    await _ejecutar(() async {
      final resultado =
          await _auth.verificarSegundoFactor(desafio.desafio, codigo.trim(), confiarDispositivo: confiarDispositivo);
      await _iniciar(resultado);
    }, alFallar: (e) {
      // Desafío vencido o agotado: hay que volver a escribir la contraseña.
      if (e.statusCode == 400) {
        _desafio = null;
        _set(SessionStatus.unauthenticated, null);
      }
    });
  }

  void cancelarSegundoFactor() {
    _desafio = null;
    _error = null;
    _aviso = null;
    _set(SessionStatus.unauthenticated, null);
  }

  /// Tras cambiar la contraseña o desactivar el 2FA el servidor emite un token nuevo (el anterior se invalidó).
  Future<void> actualizarSesion(Session nueva) async {
    await _storage.save(nueva);
    _set(SessionStatus.authenticated, nueva);
  }

  /// [expirada]: se llamó por un 401 del servidor, no por el botón de salir.
  Future<void> logout({bool expirada = false}) async {
    if (_status == SessionStatus.unauthenticated) return;
    await _storage.clear();
    _desafio = null;
    _aviso = null;
    _codigosRespaldoNuevos = null;
    _error = expirada ? 'Tu sesión expiró. Inicia sesión de nuevo.' : null;
    _set(SessionStatus.unauthenticated, null);
  }

  void limpiarMensajes() {
    _error = null;
    _aviso = null;
    notifyListeners();
  }

  Future<void> _iniciar(SesionIniciada resultado) async {
    if (resultado.tokenDispositivo != null) await _storage.guardarTokenDispositivo(resultado.tokenDispositivo!);
    _codigosRespaldoNuevos = resultado.codigosRespaldo;
    await _storage.save(resultado.session);
    _desafio = null;
    _set(SessionStatus.authenticated, resultado.session);
  }

  Future<void> _ejecutar(Future<void> Function() accion, {void Function(ApiException e)? alFallar}) async {
    if (_procesando) return;
    _procesando = true;
    _error = null;
    _aviso = null;
    notifyListeners();
    try {
      await accion();
    } on ApiException catch (e) {
      _error = e.message;
      alFallar?.call(e);
    } on TypeError {
      _error = ApiClient.respuestaInesperada;
    } finally {
      _procesando = false;
      notifyListeners();
    }
  }

  void _set(SessionStatus status, Session? session) {
    _status = status;
    _session = session;
    notifyListeners();
  }
}
