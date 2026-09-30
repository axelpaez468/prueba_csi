import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pedidos_app/core/network/api_client.dart';
import 'package:pedidos_app/data/repositories/auth_repository.dart';
import 'package:pedidos_app/features/auth/session_controller.dart';

import '../infra/storage_en_memoria.dart';

const _sesion = {
  'token': 'jwt',
  'expiraEn': '2100-01-01T00:00:00Z',
  'username': 'admin',
  'email': 'admin@pedidos.local',
  'rol': 'ADMIN',
  'requiereSegundoFactor': false,
};

void main() {
  late List<http.Request> enviados;
  late StorageEnMemoria storage;

  SessionController crear(http.Response Function(http.Request) responder) {
    enviados = [];
    storage = StorageEnMemoria();
    final api = ApiClient(
      baseUrl: 'http://api.test',
      tokenProvider: () async => null,
      httpClient: MockClient((req) async {
        enviados.add(req);
        return responder(req);
      }),
    );
    return SessionController(AuthRepository(api), storage);
  }

  http.Response json(Object cuerpo, [int estado = 200]) => http.Response(jsonEncode(cuerpo), estado,
      headers: {'content-type': 'application/json; charset=utf-8'});

  test('login con 2FA: pide el código y con el código correcto inicia sesión y guarda el dispositivo', () async {
    final session = crear((req) => req.url.path == '/api/auth/login'
        ? json({'requiereSegundoFactor': true, 'desafio': 'd-123', 'metodo': 'SMS', 'destino': '+502 •••• 0101'})
        : json({..._sesion, 'tokenDispositivo': 'disp-456'}));
    await session.restore();

    await session.login('admin@pedidos.local', 'clave', recordar: true);
    expect(session.status, SessionStatus.segundoFactor);
    expect(session.desafio!.destino, '+502 •••• 0101');
    expect(storage.emailRecordado, 'admin@pedidos.local');

    await session.verificarCodigo('123456', confiarDispositivo: true);
    expect(session.status, SessionStatus.authenticated);
    expect(session.session!.email, 'admin@pedidos.local');
    expect(storage.tokenDispositivo, 'disp-456');
    expect(jsonDecode(enviados.last.body), {'desafio': 'd-123', 'codigo': '123456', 'confiarDispositivo': true});
  });

  test('el siguiente login envía el token de dispositivo de confianza', () async {
    final session = crear((_) => json(_sesion));
    storage.tokenDispositivo = 'disp-456';
    await session.restore();

    await session.login('admin@pedidos.local', 'clave');

    expect(session.status, SessionStatus.authenticated);
    expect(jsonDecode(enviados.single.body)['tokenDispositivo'], 'disp-456');
  });

  test('un código incorrecto muestra el error y deja al usuario en el segundo paso', () async {
    final session = crear((req) => req.url.path == '/api/auth/login'
        ? json({'requiereSegundoFactor': true, 'desafio': 'd', 'metodo': 'TOTP'})
        : json({'error': 'El código no es correcto o ya expiró.'}, 401));
    await session.restore();
    await session.login('admin@pedidos.local', 'clave');

    await session.verificarCodigo('000000');

    expect(session.status, SessionStatus.segundoFactor);
    expect(session.error, contains('no es correcto'));
  });

  test('un desafío vencido (400) devuelve al login', () async {
    final session = crear((req) => req.url.path == '/api/auth/login'
        ? json({'requiereSegundoFactor': true, 'desafio': 'd', 'metodo': 'TOTP'})
        : json({'error': 'La verificación expiró. Inicia sesión de nuevo.'}, 400));
    await session.restore();
    await session.login('admin@pedidos.local', 'clave');

    await session.verificarCodigo('123456');

    expect(session.status, SessionStatus.unauthenticated);
    expect(session.error, contains('expiró'));
  });
}
