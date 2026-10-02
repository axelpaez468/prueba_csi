import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pedidos_app/core/network/api_client.dart';
import 'package:pedidos_app/core/security/session.dart';
import 'package:pedidos_app/core/theme/app_theme.dart';
import 'package:pedidos_app/data/repositories/auth_repository.dart';
import 'package:pedidos_app/data/repositories/cuenta_repository.dart';
import 'package:pedidos_app/data/repositories/erp_repositories.dart';
import 'package:pedidos_app/data/repositories/pedido_repository.dart';
import 'package:pedidos_app/data/repositories/producto_repository.dart';
import 'package:pedidos_app/data/repositories/usuario_repository.dart';
import 'package:pedidos_app/features/auth/session_controller.dart';
import 'package:pedidos_app/features/cart/cart_controller.dart';
import 'package:pedidos_app/features/catalog/catalog_controller.dart';
import 'package:pedidos_app/features/shell/modulos.dart';
import 'package:provider/provider.dart';

import 'storage_en_memoria.dart';

/// Lo que "responde el servidor" en una prueba: cada prueba decide (errores, demoras, datos raros...).
typedef Responder = FutureOr<http.Response> Function(http.Request req);

http.Response respuestaJson(Object? cuerpo, [int status = 200]) =>
    http.Response(jsonEncode(cuerpo), status, headers: {'content-type': 'application/json; charset=utf-8'});

/// Peticiones que hizo la app durante la prueba (para contar envíos duplicados, por ejemplo).
final peticiones = <http.Request>[];

class Montaje {
  Montaje(this.api, this.session, this.carrito);

  final ApiClient api;
  final SessionController session;
  final CartController carrito;
}

/// Monta una pantalla con todas sus dependencias reales, salvo el servidor, que es [responder].
Future<Montaje> montar(
  WidgetTester tester,
  Widget pantalla, {
  required Responder responder,
  String rol = 'ADMIN',
  Size tamano = const Size(1366, 900),
  bool esperar = true,
}) async {
  tester.view
    ..physicalSize = tamano
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  peticiones.clear();

  final api = ApiClient(
    baseUrl: 'http://api.test',
    httpClient: MockClient((req) async {
      peticiones.add(req);
      return responder(req);
    }),
    tokenProvider: () async => 't',
  );
  final session = SessionController(
    AuthRepository(api),
    StorageEnMemoria(
      Session(token: 't', username: 'usuario', email: 'usuario@pedidos.local', rol: rol, expiraEn: DateTime.utc(2100)),
    ),
  );
  await session.restore();
  api.onUnauthorized = () => session.logout(expirada: true);
  final carrito = CartController(PedidoRepository(api));

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        Provider.value(value: AuthRepository(api)),
        Provider.value(value: CuentaRepository(api)),
        Provider.value(value: UsuarioRepository(api)),
        Provider.value(value: PedidoRepository(api)),
        Provider.value(value: ClienteRepository(api)),
        Provider.value(value: InventarioRepository(api)),
        Provider.value(value: CompraRepository(api)),
        Provider.value(value: ContabilidadRepository(api)),
        Provider.value(value: PanelRepository(api)),
        Provider.value(value: ReporteRepository(api)),
        Provider.value(value: ProductoRepository(api)),
        Provider.value(value: GeografiaRepository(api)),
        Provider.value(value: PipelineRepository(api)),
        ChangeNotifierProvider.value(value: session),
        ChangeNotifierProvider(create: (_) => NavegacionController()),
        ChangeNotifierProvider(create: (_) => CatalogController(ProductoRepository(api))),
        ChangeNotifierProvider.value(value: carrito),
      ],
      child: MaterialApp(theme: AppTheme.light(), home: pantalla),
    ),
  );
  if (esperar) await tester.pumpAndSettle();
  return Montaje(api, session, carrito);
}
