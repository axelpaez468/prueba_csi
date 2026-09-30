import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pedidos_app/core/network/api_client.dart';
import 'package:pedidos_app/core/security/session.dart';
import 'package:pedidos_app/core/theme/app_theme.dart';
import 'package:pedidos_app/data/models/pedido.dart';
import 'package:pedidos_app/data/models/producto.dart';
import 'package:pedidos_app/data/repositories/auth_repository.dart';
import 'package:pedidos_app/data/repositories/cuenta_repository.dart';
import 'package:pedidos_app/data/repositories/pedido_repository.dart';
import 'package:pedidos_app/data/repositories/producto_repository.dart';
import 'package:pedidos_app/features/auth/login_screen.dart';
import 'package:pedidos_app/features/auth/recuperar_password_screen.dart';
import 'package:pedidos_app/features/auth/restablecer_password_screen.dart';
import 'package:pedidos_app/features/auth/segundo_factor_screen.dart';
import 'package:pedidos_app/features/auth/session_controller.dart';
import 'package:pedidos_app/features/cart/cart_controller.dart';
import 'package:pedidos_app/features/cart/cart_screen.dart';
import 'package:pedidos_app/features/catalog/catalog_controller.dart';
import 'package:pedidos_app/features/catalog/catalog_screen.dart';
import 'package:pedidos_app/features/cuenta/bitacora_screen.dart';
import 'package:pedidos_app/features/cuenta/seguridad_screen.dart';
import 'package:pedidos_app/features/order/order_confirmation_screen.dart';
import 'package:provider/provider.dart';

import '../infra/storage_en_memoria.dart';

/// Renderiza cada pantalla en tamaños de celular, tablet y escritorio.
/// Cualquier desborde de layout ("RenderFlex overflowed") hace fallar la prueba.

const _tamanos = {
  'celular chico 320x568': Size(320, 568),
  'celular 375x812': Size(375, 812),
  'tablet 768x1024': Size(768, 1024),
  'laptop 1366x768': Size(1366, 768),
  'escritorio 1920x1080': Size(1920, 1080),
};

final _productos = [
  const Producto(id: 1, codigo: 'P-001', nombre: 'Teclado mecánico', precio: 450, stock: 25),
  const Producto(id: 2, codigo: 'P-002', nombre: 'Mouse inalámbrico', precio: 125.5, stock: 3),
  const Producto(id: 3, codigo: 'P-003', nombre: 'Monitor 27" con nombre largo para probar el ajuste', precio: 2350, stock: 1),
  const Producto(id: 4, codigo: 'P-004', nombre: 'Audífonos USB', precio: 199.99, stock: 12),
  const Producto(id: 5, codigo: 'P-005', nombre: 'Webcam HD', precio: 310, stock: 0),
];

final _accesos = [
  for (final (evento, exito) in [('LOGIN_EXITOSO', true), ('2FA_FALLIDO', false), ('DISPOSITIVO_NUEVO', true)])
    {
      'fecha': '2026-09-29T15:30:00Z',
      'email': 'usuario-con-correo-bastante-largo@empresa-de-ejemplo.com',
      'evento': evento,
      'exito': exito,
      'ip': '203.0.113.200',
      'dispositivo': 'Chrome en Windows',
      'detalle': null,
    }
];

/// API simulada: responde según la ruta.
http.Response _responder(http.Request req) {
  final cuerpo = switch (req.url.path) {
    '/api/productos' => [
        for (final p in _productos)
          {'id': p.id, 'codigo': p.codigo, 'nombre': p.nombre, 'precio': p.precio, 'stock': p.stock},
      ],
    '/api/cuenta/seguridad' => {
        'email': 'usuario-con-correo-bastante-largo@empresa-de-ejemplo.com',
        'metodo': 'SMS',
        'telefonoEnmascarado': '+502 •••• 0101',
        'codigosRespaldoRestantes': 2,
        'dosFactorObligatorio': true,
      },
    '/api/cuenta/accesos' || '/api/admin/bitacora' => _accesos,
    '/api/auth/login' => {'requiereSegundoFactor': true, 'desafio': 'd', 'metodo': 'SMS', 'destino': '+502 •••• 0101'},
    _ => <String, dynamic>{},
  };
  return http.Response(jsonEncode(cuerpo), 200, headers: {'content-type': 'application/json; charset=utf-8'});
}

ApiClient _api() => ApiClient(
      baseUrl: 'http://api.test',
      tokenProvider: () async => 'token',
      httpClient: MockClient((req) async => _responder(req)),
    );

enum _Sesion { anonima, autenticada, segundoFactor }

Future<void> _montar(WidgetTester tester, Size tamano, Widget pantalla, {_Sesion sesion = _Sesion.autenticada}) async {
  tester.view
    ..physicalSize = tamano
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final api = _api();
  final auth = AuthRepository(api);
  final session = SessionController(
    auth,
    StorageEnMemoria(sesion == _Sesion.autenticada
        ? Session(token: 't', username: 'vendedor', email: 'vendedor@pedidos.local', rol: 'ADMIN', expiraEn: DateTime.utc(2100))
        : null),
  );
  await session.restore();
  if (sesion == _Sesion.segundoFactor) await session.login('admin@pedidos.local', 'x');

  final catalogo = CatalogController(ProductoRepository(api));
  final carrito = CartController(PedidoRepository(api))
    ..agregar(_productos[0], 2)
    ..agregar(_productos[1], 1)
    ..agregar(_productos[2], 1);

  await tester.pumpWidget(MultiProvider(
    providers: [
      Provider.value(value: auth),
      Provider.value(value: CuentaRepository(api)),
      ChangeNotifierProvider.value(value: session),
      ChangeNotifierProvider.value(value: catalogo),
      ChangeNotifierProvider.value(value: carrito),
    ],
    child: MaterialApp(theme: AppTheme.light(), home: pantalla),
  ));
  await tester.pumpAndSettle();
}

final _pedido = Pedido(
  numero: 1234,
  fecha: DateTime.utc(2026, 9, 29, 15, 30),
  total: 3375.5,
  lineas: [
    for (final (p, c) in [(_productos[0], 2), (_productos[1], 1), (_productos[2], 1)])
      PedidoLinea(
        productoId: p.id,
        codigo: p.codigo,
        nombre: p.nombre,
        cantidad: c,
        precioUnitario: p.precio,
        subtotal: p.precio * c,
      ),
  ],
);

void main() {
  for (final MapEntry(key: nombre, value: tamano) in _tamanos.entries) {
    group(nombre, () {
      testWidgets('login', (tester) async {
        await _montar(tester, tamano, const LoginScreen(), sesion: _Sesion.anonima);
        expect(find.text('Iniciar sesión'), findsOneWidget);
        expect(find.text('¿Olvidaste tu contraseña?'), findsOneWidget);
      });

      testWidgets('verificación en dos pasos', (tester) async {
        await _montar(tester, tamano, const SegundoFactorScreen(), sesion: _Sesion.segundoFactor);
        expect(find.text('Verificación en dos pasos'), findsOneWidget);
        expect(find.textContaining('+502 •••• 0101'), findsOneWidget);
      });

      testWidgets('recuperar contraseña', (tester) async {
        await _montar(tester, tamano, const RecuperarPasswordScreen(), sesion: _Sesion.anonima);
        expect(find.text('Enviar enlace'), findsOneWidget);
      });

      testWidgets('restablecer contraseña', (tester) async {
        await _montar(tester, tamano, RestablecerPasswordScreen(token: 't', alTerminar: () {}), sesion: _Sesion.anonima);
        expect(find.text('Guardar contraseña'), findsOneWidget);
      });

      testWidgets('catálogo', (tester) async {
        await _montar(tester, tamano, const CatalogScreen());
        expect(find.text('Teclado mecánico'), findsOneWidget);
      });

      testWidgets('carrito', (tester) async {
        await _montar(tester, tamano, const CartScreen());
        expect(find.text('Confirmar pedido'), findsOneWidget);
      });

      testWidgets('confirmación', (tester) async {
        await _montar(tester, tamano, OrderConfirmationScreen(pedido: _pedido));
        expect(find.byKey(const Key('total-pedido')), findsOneWidget);
      });

      testWidgets('seguridad de la cuenta', (tester) async {
        await _montar(tester, tamano, const SeguridadScreen());
        expect(find.text('Verificación en dos pasos'), findsOneWidget);
        expect(find.text('Cambiar contraseña'), findsOneWidget);
      });

      testWidgets('bitácora de accesos', (tester) async {
        await _montar(tester, tamano, const BitacoraScreen());
        expect(find.text('Bitácora de accesos'), findsOneWidget);
      });
    });
  }
}
