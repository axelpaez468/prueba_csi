import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:pedidos_app/core/network/api_client.dart';
import 'package:pedidos_app/data/models/erp.dart';
import 'package:pedidos_app/features/auth/session_controller.dart';
import 'package:pedidos_app/features/catalog/producto_detalle_screen.dart';
import 'package:pedidos_app/features/compras/ordenes_screen.dart';
import 'package:pedidos_app/features/contabilidad/cuentas_screen.dart';
import 'package:pedidos_app/features/cuenta/seguridad_screen.dart';
import 'package:pedidos_app/features/inventario/inventario_screen.dart';
import 'package:pedidos_app/features/shell/modulos.dart';
import 'package:pedidos_app/data/models/producto.dart';
import 'package:pedidos_app/features/ventas/ventas_screen.dart';

import '../infra/montaje.dart';

/// Qué ve el usuario cuando el servidor falla de cada forma posible, en cada pantalla del ERP.
/// Ninguna pantalla debe quedarse en blanco, cargando para siempre o lanzar una excepción.

const _falla = 'Falla simulada del servidor';

/// Todas las pantallas del menú (como administrador, que ve todas) y las de detalle.
final _pantallas = <String, Widget Function()>{
  for (final m in modulos) m.titulo: m.pantalla,
  'Detalle de venta': () => const VentaDetalleScreen(numero: 1),
  'Detalle de orden de compra': () => const OrdenDetalleScreen(numero: 1),
  'Kardex': () => const KardexScreen(productoId: 1),
  'Libro mayor': () => LibroMayorScreen(
    cuenta: CuentaContable.fromJson(const {
      'id': 1,
      'codigo': '1101',
      'nombre': 'Caja',
      'tipo': 'ACTIVO',
      'activa': true,
      'esSistema': true,
      'saldo': 0,
    }),
  ),
  'Seguridad de la cuenta': () => const SeguridadScreen(),
  'Ficha de producto': () => const ProductoDetalleScreen(
    producto: Producto(id: 1, codigo: 'P-001', nombre: 'Teclado mecánico', precio: 450, stock: 25),
  ),
};

/// Cada forma en que puede fallar el servidor y lo que el usuario debe leer.
final _fallas = <String, (Responder, String)>{
  'error 500': ((_) => respuestaJson({'error': _falla}, 500), _falla),
  'error 500 sin cuerpo': ((_) => http.Response('', 500), 'error en el servidor'),
  'error 502 del proxy (HTML)': ((_) => http.Response('<html><body>Bad Gateway</body></html>', 502), 'error en el servidor'),
  'sin conexión': ((_) => throw http.ClientException('sin red'), 'No se pudo conectar'),
  '200 con HTML (proxy mal configurado)': ((_) => http.Response('<!doctype html><html></html>', 200), 'respuesta inesperada'),
  '200 con datos de otra forma': ((_) => respuestaJson({'inesperado': true}), 'respuesta inesperada'),
  '403 sin permisos': (
    (_) => respuestaJson({'error': 'No tiene permisos para realizar esta operación.'}, 403),
    'No tiene permisos',
  ),
  '429 demasiadas solicitudes': (
    (_) => respuestaJson({'error': 'Demasiadas solicitudes. Espere un momento e intente de nuevo.'}, 429),
    'Demasiadas solicitudes',
  ),
};

void main() {
  for (final MapEntry(key: nombre, value: pantalla) in _pantallas.entries) {
    group(nombre, () {
      for (final MapEntry(key: caso, value: (responder, mensaje)) in _fallas.entries) {
        testWidgets(caso, (tester) async {
          await montar(tester, pantalla(), responder: responder);

          expect(
            find.textContaining(mensaje, findRichText: true),
            findsWidgets,
            reason: 'La pantalla debe explicar qué pasó ("$mensaje")',
          );
          expect(find.byType(LinearProgressIndicator), findsNothing, reason: 'No debe quedarse cargando');
        });
      }

      testWidgets('después de un error, "Reintentar" vuelve a pedir los datos', (tester) async {
        await montar(tester, pantalla(), responder: (_) => respuestaJson({'error': _falla}, 500));
        final reintentar = find.text('Reintentar');
        if (reintentar.evaluate().isEmpty) return; // pantallas sin carga propia (p. ej. formularios)
        final antes = peticiones.length;

        await tester.ensureVisible(reintentar.first);
        await tester.tap(reintentar.first);
        await tester.pumpAndSettle();

        expect(peticiones.length, greaterThan(antes));
      });

      testWidgets('mientras el servidor tarda, se ve que está cargando', (tester) async {
        final respuesta = Completer<http.Response>();
        await montar(tester, pantalla(), responder: (_) => respuesta.future, esperar: false);
        await tester.pump(const Duration(milliseconds: 100));

        expect(find.byWidgetPredicate((w) => w is LinearProgressIndicator || w is CircularProgressIndicator), findsWidgets);

        respuesta.complete(respuestaJson({'error': _falla}, 500));
        await tester.pumpAndSettle();
      });

      testWidgets('si la sesión venció (401), vuelve al inicio de sesión', (tester) async {
        // Sin esperar a que "termine": tras un 401 la app real cambia al login, la pantalla no sigue sola.
        final m = await montar(
          tester,
          pantalla(),
          responder: (_) => respuestaJson({'error': 'Sesión no válida o expirada. Inicie sesión de nuevo.'}, 401),
          esperar: false,
        );
        for (var i = 0; i < 5; i++) {
          await tester.pump(const Duration(milliseconds: 50));
        }

        expect(m.session.status, SessionStatus.unauthenticated);
        expect(m.session.error, contains('expiró'));
      });
    });
  }

  test('el mensaje de respuesta inesperada se puede mostrar tal cual al usuario', () {
    expect(ApiClient.respuestaInesperada, isNot(contains('Exception')));
  });

  test('todos los módulos del menú están en la lista de pantallas probadas', () {
    expect(_pantallas.keys, containsAll(modulos.map((m) => m.titulo)));
  });

  testWidgets('el detalle de venta inexistente (404) lo dice, no queda vacío', (tester) async {
    await montar(
      tester,
      const VentaDetalleScreen(numero: 99999),
      responder: (_) => respuestaJson({'error': 'Venta no encontrada.'}, 404),
    );
    expect(find.textContaining('no encontrada'), findsWidgets);
  });

  testWidgets('una respuesta lenta que llega después de salir de la pantalla no causa errores', (tester) async {
    final respuesta = Completer<http.Response>();
    await montar(tester, const InventarioScreen(), responder: (_) => respuesta.future, esperar: false);
    await tester.pump();
    await tester.pumpWidget(const SizedBox()); // el usuario se fue a otra pantalla
    respuesta.complete(respuestaJson([]));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('las cuentas contables con error muestran el mensaje en la tabla', (tester) async {
    await montar(tester, const CuentasScreen(), responder: (_) => respuestaJson({'error': _falla}, 500));
    expect(find.textContaining(_falla), findsWidgets);
  });
}
