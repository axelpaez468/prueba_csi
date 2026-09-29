import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pedidos_app/core/network/api_client.dart';
import 'package:pedidos_app/core/network/api_exception.dart';
import 'package:pedidos_app/data/models/pedido.dart';
import 'package:pedidos_app/data/repositories/pedido_repository.dart';

const _respuestaServidor = {
  'numero': 42,
  'fecha': '2026-09-28T17:06:14Z',
  'usuarioId': 1,
  'total': 1025.50,
  'lineas': [
    {'productoId': 1, 'codigo': 'P-001', 'nombre': 'Teclado', 'cantidad': 2, 'precioUnitario': 450.00, 'subtotal': 900.00},
    {'productoId': 2, 'codigo': 'P-002', 'nombre': 'Mouse', 'cantidad': 1, 'precioUnitario': 125.50, 'subtotal': 125.50},
  ],
};

void main() {
  late http.Request? enviado;
  var llamadasUnauthorized = 0;

  PedidoRepository crearRepo(http.Response Function(http.Request) responder) {
    enviado = null;
    llamadasUnauthorized = 0;
    final api = ApiClient(
      baseUrl: 'http://api.test',
      httpClient: MockClient((req) async {
        enviado = req;
        return responder(req);
      }),
      tokenProvider: () async => 'token-de-prueba',
    )..onUnauthorized = () => llamadasUnauthorized++;
    return PedidoRepository(api);
  }

  const lineas = [LineaPedido(productoId: 1, cantidad: 2), LineaPedido(productoId: 2, cantidad: 1)];

  test('envía solo productoId y cantidad, con el token Bearer', () async {
    final repo = crearRepo((_) => http.Response(jsonEncode(_respuestaServidor), 201));

    await repo.crear(lineas);

    expect(enviado!.method, 'POST');
    expect(enviado!.url.toString(), 'http://api.test/api/pedidos');
    expect(enviado!.headers['Authorization'], 'Bearer token-de-prueba');
    expect(jsonDecode(enviado!.body), {
      'lineas': [
        {'productoId': 1, 'cantidad': 2},
        {'productoId': 2, 'cantidad': 1},
      ],
    });
    expect(enviado!.body, isNot(contains('precio')));
    expect(enviado!.body, isNot(contains('total')));
  });

  test('usa el número y el total que devuelve el servidor', () async {
    final repo = crearRepo((_) => http.Response(jsonEncode(_respuestaServidor), 201));

    final pedido = await repo.crear(lineas);

    expect(pedido.numero, 42);
    expect(pedido.total, 1025.50);
    expect(pedido.lineas.map((l) => l.subtotal), [900.00, 125.50]);
  });

  test('un 400 se convierte en ApiException con el mensaje del servidor', () async {
    final repo = crearRepo((_) => http.Response(
          jsonEncode({'error': "Stock insuficiente para 'Monitor': solicitado 2, disponible 1."}),
          400,
        ));

    await expectLater(
      repo.crear(lineas),
      throwsA(isA<ApiException>()
          .having((e) => e.statusCode, 'statusCode', 400)
          .having((e) => e.message, 'message', contains('Stock insuficiente'))),
    );
    expect(llamadasUnauthorized, 0);
  });

  test('un 401 dispara el cierre de sesión', () async {
    final repo = crearRepo((_) => http.Response(jsonEncode({'error': 'Sesión expirada'}), 401));

    await expectLater(repo.crear(lineas), throwsA(isA<UnauthorizedException>()));
    expect(llamadasUnauthorized, 1);
  });
}
