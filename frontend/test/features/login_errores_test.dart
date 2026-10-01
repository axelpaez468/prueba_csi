import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pedidos_app/core/network/api_client.dart';
import 'package:pedidos_app/data/repositories/auth_repository.dart';
import 'package:pedidos_app/features/auth/session_controller.dart';

import '../infra/storage_en_memoria.dart';

/// El inicio de sesión cuando el servidor falla: siempre un mensaje claro y el formulario listo para reintentar.
void main() {
  SessionController crear(Future<http.Response> Function(http.Request) responder) {
    final api = ApiClient(baseUrl: 'http://api.test', tokenProvider: () async => null, httpClient: MockClient(responder));
    return SessionController(AuthRepository(api), StorageEnMemoria());
  }

  http.Response json(Object cuerpo, int status) =>
      http.Response(jsonEncode(cuerpo), status, headers: {'content-type': 'application/json; charset=utf-8'});

  final casos = <String, (Future<http.Response> Function(http.Request), String)>{
    'contraseña incorrecta (401)': ((_) async => json({'error': 'Correo o contraseña incorrectos.'}, 401), 'incorrectos'),
    'cuenta bloqueada (429)': (
      (_) async => json({'error': 'Demasiados intentos fallidos. Intenta de nuevo en 5 minuto(s).'}, 429),
      'Demasiados',
    ),
    'cuenta desactivada (403)': (
      (_) async => json({'error': 'Tu cuenta está desactivada. Contacta al administrador.'}, 403),
      'desactivada',
    ),
    'error del servidor (500)': ((_) async => http.Response('', 500), 'error en el servidor'),
    'sin conexión': ((_) async => throw http.ClientException('sin red'), 'No se pudo conectar'),
    '200 con HTML': ((_) async => http.Response('<html></html>', 200), 'respuesta inesperada'),
    '200 sin token': ((_) async => json({'algo': 1}, 200), 'respuesta inesperada'),
  };

  for (final MapEntry(key: caso, value: (responder, mensaje)) in casos.entries) {
    test(caso, () async {
      final s = crear(responder);
      await s.restore();

      await s.login('admin@pedidos.local', 'una-clave-cualquiera');

      expect(s.status, SessionStatus.unauthenticated);
      expect(s.error, contains(mensaje));
      expect(s.procesando, isFalse, reason: 'El botón debe quedar habilitado para reintentar');
    });
  }

  test('código de Google Authenticator con el servidor caído: mensaje y sigue en el segundo paso', () async {
    var paso = 0;
    final s = crear((req) async {
      paso++;
      return paso == 1
          ? json({'requiereSegundoFactor': true, 'desafio': 'd', 'metodo': 'TOTP'}, 200)
          : throw http.ClientException('sin red');
    });
    await s.restore();
    await s.login('admin@pedidos.local', 'clave');
    expect(s.status, SessionStatus.segundoFactor);

    await s.verificarCodigo('123456');

    expect(s.status, SessionStatus.segundoFactor);
    expect(s.error, contains('No se pudo conectar'));
  });
}
