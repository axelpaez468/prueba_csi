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
import 'package:pedidos_app/data/repositories/erp_repositories.dart';
import 'package:pedidos_app/data/repositories/pedido_repository.dart';
import 'package:pedidos_app/data/repositories/producto_repository.dart';
import 'package:pedidos_app/data/repositories/usuario_repository.dart';
import 'package:pedidos_app/features/auth/login_screen.dart';
import 'package:pedidos_app/features/auth/recuperar_password_screen.dart';
import 'package:pedidos_app/features/auth/restablecer_password_screen.dart';
import 'package:pedidos_app/features/auth/segundo_factor_screen.dart';
import 'package:pedidos_app/features/auth/session_controller.dart';
import 'package:pedidos_app/features/cart/cart_controller.dart';
import 'package:pedidos_app/features/cart/cart_screen.dart';
import 'package:pedidos_app/features/catalog/catalog_controller.dart';
import 'package:pedidos_app/features/catalog/catalog_screen.dart';
import 'package:pedidos_app/features/clientes/clientes_screen.dart';
import 'package:pedidos_app/features/clientes/tercero_form_dialog.dart';
import 'package:pedidos_app/features/compras/ordenes_screen.dart';
import 'package:pedidos_app/features/compras/proveedores_screen.dart';
import 'package:pedidos_app/features/contabilidad/cuentas_screen.dart';
import 'package:pedidos_app/features/contabilidad/libro_diario_screen.dart';
import 'package:pedidos_app/features/contabilidad/reportes_screen.dart';
import 'package:pedidos_app/features/cuenta/bitacora_screen.dart';
import 'package:pedidos_app/features/cuenta/seguridad_screen.dart';
import 'package:pedidos_app/features/inventario/inventario_dialogs.dart';
import 'package:pedidos_app/features/inventario/inventario_screen.dart';
import 'package:pedidos_app/features/panel/panel_screen.dart';
import 'package:pedidos_app/features/order/order_confirmation_screen.dart';
import 'package:pedidos_app/features/usuarios/usuario_form_dialog.dart';
import 'package:pedidos_app/features/usuarios/usuarios_screen.dart';
import 'package:pedidos_app/features/ventas/ventas_screen.dart';
import 'package:pedidos_app/data/models/erp.dart';
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

const _nombreLargo = 'Distribuidora Tecnológica Centroamericana del Pacífico, Sociedad Anónima';

Map<String, dynamic> _productoInv(int i) => {
      'id': i,
      'codigo': 'P-00$i',
      'nombre': i == 3 ? 'Monitor 27" con nombre largo para probar el ajuste' : 'Producto $i',
      'precio': 2350.0,
      'stock': i == 3 ? 0 : 12000,
      'stockMinimo': 5,
      'costoPromedio': 1258.9286,
      'valorInventario': 15107142.86,
      'activo': i != 5,
      'bajoMinimo': i == 3,
      'margen': 40.1,
    };

final _cuentas = [
  for (final (i, (codigo, nombre, tipo)) in [
    ('1102', 'Bancos', 'ACTIVO'),
    ('1103', 'Inventario de mercadería', 'ACTIVO'),
    ('2102', 'IVA por pagar (débito fiscal)', 'PASIVO'),
    ('3101', 'Capital social', 'CAPITAL'),
    ('4101', 'Ventas', 'INGRESO'),
    ('6103', 'Energía eléctrica, agua y teléfono', 'GASTO'),
  ].indexed)
    {'id': i + 1, 'codigo': codigo, 'nombre': nombre, 'tipo': tipo, 'activa': true, 'esSistema': i < 5, 'saldo': 1234567.89},
];

List<Map<String, dynamic>> _renglones(String codigo) =>
    [{'codigo': codigo, 'cuenta': 'Cuenta con un nombre largo para el reporte', 'monto': 9876543.21}];

final _lineaPartida = [
  {'cuentaId': 1, 'codigo': '1102', 'cuenta': 'Bancos', 'debe': 1234567.89, 'haber': 0},
  {'cuentaId': 3, 'codigo': '2102', 'cuenta': 'IVA por pagar (débito fiscal) con nombre largo', 'debe': 0, 'haber': 1234567.89},
];

Object? _respuestaErp(String ruta) => switch (ruta) {
      '/api/panel' => {
          'ventasHoy': 12345.67,
          'cantidadVentasHoy': 3,
          'ventasMes': 1234567.89,
          'cantidadVentasMes': 120,
          'utilidadBrutaMes': 345678.9,
          'comprasMes': 98765.43,
          'valorInventario': 2345678.9,
          'ordenesPendientes': 2,
          'productosBajoMinimo': [
            {'id': 3, 'codigo': 'P-003', 'nombre': 'Monitor 27" con nombre largo para probar el ajuste', 'stock': 0, 'stockMinimo': 2},
          ],
          'ventasUltimos7Dias': [
            for (var d = 24; d <= 30; d++) {'fecha': '2026-09-$d', 'total': d * 1000.0},
          ],
        },
      '/api/clientes' => [
          {'id': 1, 'nit': 'CF', 'nitFormateado': 'CF', 'nombre': 'Consumidor Final', 'direccion': 'Ciudad', 'telefono': null,
            'email': null, 'activo': true, 'esConsumidorFinal': true},
          {'id': 2, 'nit': '12345679', 'nitFormateado': '1234567-9', 'nombre': _nombreLargo, 'direccion': '6a. avenida 10-20, zona 1',
            'telefono': '+50222330101', 'email': 'facturacion.cliente@empresa-ejemplo.com.gt', 'activo': false, 'esConsumidorFinal': false},
        ],
      '/api/pedidos' => [
          for (var i = 1; i <= 3; i++)
            {'numero': 1000 + i, 'serie': 'A', 'fecha': '2026-09-30T15:30:00Z', 'clienteNit': '1234567-9', 'clienteNombre': _nombreLargo,
              'vendedor': 'María Fernanda Hernández de la Cruz', 'formaPago': 'TRANSFERENCIA', 'productos': 3, 'total': 1234567.89},
        ],
      '/api/pedidos/1234' => {
          'numero': 1234, 'fecha': '2026-09-29T15:30:00Z', 'usuarioId': 1, 'total': 3375.5, 'serie': 'A',
          'autorizacion': '3f2504e0-4f89-11d3-9a0c-0305e82c3301', 'clienteId': 2, 'clienteNit': '1234567-9', 'clienteNombre': _nombreLargo,
          'clienteDireccion': '6a. avenida 10-20, zona 1', 'vendedor': 'Vendedor Demo', 'formaPago': 'EFECTIVO',
          'baseImponible': 3013.84, 'iva': 361.66,
          'lineas': [
            {'productoId': 1, 'codigo': 'P-001', 'nombre': 'Teclado mecánico', 'cantidad': 2, 'precioUnitario': 450, 'subtotal': 900},
          ],
        },
      '/api/inventario/productos' => [for (var i = 1; i <= 5; i++) _productoInv(i)],
      '/api/inventario/productos/3/kardex' => {
          'producto': _productoInv(3),
          'movimientos': [
            for (final (i, (tipo, cant)) in [('INICIAL', 25), ('COMPRA', 10000), ('VENTA', -2), ('AJUSTE_SALIDA', -1)].indexed)
              {'id': i + 1, 'fecha': '2026-09-30T15:30:00Z', 'tipo': tipo, 'cantidad': cant, 'costoUnitario': 1258.9286, 'saldo': 12000,
                'costoPromedio': 1258.9286, 'referencia': 'OC-15, factura A-000458 del proveedor', 'usuario': 'Bodega Demo'},
          ],
        },
      '/api/compras/proveedores' => [
          {'id': 1, 'nit': '33445567', 'nitFormateado': '3344556-7', 'nombre': _nombreLargo, 'contacto': 'Ana Lucía Pérez',
            'telefono': '+50222220101', 'email': 'ventas@distribuidora-ejemplo.com.gt', 'direccion': 'Zona 4', 'activo': true},
        ],
      '/api/compras/ordenes' => [
          for (final (i, estado) in ['PENDIENTE', 'RECIBIDA', 'ANULADA'].indexed)
            {'numero': 7 + i, 'fecha': '2026-09-30T15:30:00Z', 'estado': estado, 'proveedorNombre': _nombreLargo, 'productos': 4,
              'total': 1234567.89, 'facturaProveedor': estado == 'RECIBIDA' ? 'A-000458' : null},
        ],
      '/api/compras/ordenes/7' => {
          'numero': 7, 'fecha': '2026-09-30T15:30:00Z', 'estado': 'PENDIENTE', 'proveedorId': 1, 'proveedorNit': '3344556-7',
          'proveedorNombre': _nombreLargo, 'subtotal': 1100, 'iva': 132, 'total': 1232, 'observaciones': 'Reposición urgente',
          'creadaPor': 'Compras Demo', 'fechaRecepcion': null, 'recibidaPor': null, 'facturaProveedor': null,
          'lineas': [
            {'productoId': 3, 'codigo': 'P-003', 'nombre': 'Monitor 27" con nombre largo para probar el ajuste', 'cantidad': 10000,
              'costoUnitario': 1100, 'subtotal': 11000000},
          ],
        },
      '/api/contabilidad/cuentas' => _cuentas,
      '/api/contabilidad/partidas' => [
          for (final origen in ['APERTURA', 'VENTA', 'MANUAL'])
            {'numero': 1, 'fecha': '2026-09-30', 'concepto': 'Factura A-15 a $_nombreLargo, efectivo', 'origen': origen,
              'referenciaId': 15, 'total': 1234567.89, 'creadoEn': '2026-09-30T15:30:00Z', 'lineas': _lineaPartida},
        ],
      '/api/contabilidad/reportes/mayor/1' => {
          'cuenta': _cuentas[0], 'desde': '2026-09-01', 'hasta': '2026-09-30', 'saldoInicial': 100000, 'totalDebe': 1234567.89,
          'totalHaber': 234567.89, 'saldoFinal': 1100000,
          'movimientos': [
            {'fecha': '2026-09-30', 'partida': 12, 'concepto': 'Compra OC-1 a $_nombreLargo', 'debe': 0, 'haber': 2139.2, 'saldo': 97860.8},
          ],
        },
      '/api/contabilidad/reportes/balance-comprobacion' => {
          'desde': '2026-09-01', 'hasta': '2026-09-30', 'totalDebe': 1234567.89, 'totalHaber': 1234567.89, 'totalSaldoDeudor': 1000,
          'totalSaldoAcreedor': 1000, 'cuadra': true,
          'filas': [
            {'codigo': '1102', 'cuenta': 'Bancos con un nombre bastante largo', 'tipo': 'ACTIVO', 'debe': 1234567.89, 'haber': 234567.89,
              'saldoDeudor': 1000000, 'saldoAcreedor': 0},
          ],
        },
      '/api/contabilidad/reportes/estado-resultados' => {
          'desde': '2026-09-01', 'hasta': '2026-09-30', 'ingresos': _renglones('4101'), 'totalIngresos': 9876543.21,
          'costos': _renglones('5101'), 'totalCostos': 1234567.89, 'utilidadBruta': 8641975.32, 'gastos': _renglones('6103'),
          'totalGastos': 123.45, 'utilidadNeta': -8641851.87,
        },
      '/api/contabilidad/reportes/balance-general' => {
          'al': '2026-09-30', 'activos': _renglones('1102'), 'totalActivos': 9876543.21, 'pasivos': _renglones('2102'),
          'totalPasivos': 1234567.89, 'capital': _renglones('3101'), 'resultadoDelEjercicio': -1472.14, 'totalCapital': 8641975.32,
          'totalPasivoYCapital': 9876543.21, 'cuadra': true,
        },
      _ => null,
    };

/// Método que devuelve el login simulado: 'TOTP' (verificar) o 'CONFIGURAR' (primer ingreso de un admin).
var _metodoLogin = 'TOTP';

/// API simulada: responde según la ruta.
http.Response _responder(http.Request req) {
  final cuerpo = switch (req.url.path) {
    '/api/productos' => [
        for (final p in _productos)
          {'id': p.id, 'codigo': p.codigo, 'nombre': p.nombre, 'precio': p.precio, 'stock': p.stock},
      ],
    '/api/cuenta/seguridad' => {
        'email': 'usuario-con-correo-bastante-largo@empresa-de-ejemplo.com',
        'metodo': 'TOTP',
        'codigosRespaldoRestantes': 2,
        'dosFactorObligatorio': true,
      },
    '/api/cuenta/accesos' || '/api/admin/bitacora' => _accesos,
    '/api/admin/usuarios' => [
        for (final (i, (nombre, rol, activo, pass)) in [
          ('María Fernanda', 'ADMIN', true, true),
          ('José Alejandro', 'VENDEDOR', true, false),
          ('Ana Lucía', 'VENDEDOR', false, true),
        ].indexed)
          {
            'id': i + 1,
            'nombre': nombre,
            'apellido': 'Hernández de la Cruz',
            'nombreCompleto': '$nombre Hernández de la Cruz',
            'email': 'usuario.con.correo.largo$i@empresa-ejemplo.com.gt',
            'telefono': '+5025555010$i',
            'codigoCorporativo': 'VEN-000$i',
            'rol': rol,
            'activo': activo,
            'dosFactor': rol == 'ADMIN' ? 'SMS' : 'NINGUNO',
            'tieneContrasena': pass,
            'creadoEn': '2026-09-29T15:30:00Z',
          },
      ],
    '/api/auth/login' => {'requiereSegundoFactor': true, 'desafio': 'd', 'metodo': _metodoLogin, 'secreto': 'JBSWY3DPEHPK3PXPJBSWY3DPEHPK3PXP', 'uri': 'otpauth://totp/Sistema%20de%20Pedidos:admin@pedidos.local?secret=JBSWY3DPEHPK3PXP&issuer=Sistema%20de%20Pedidos'},
    final ruta => _respuestaErp(ruta) ?? <String, dynamic>{},
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
      Provider.value(value: UsuarioRepository(api)),
      Provider.value(value: PedidoRepository(api)),
      Provider.value(value: ClienteRepository(api)),
      Provider.value(value: InventarioRepository(api)),
      Provider.value(value: CompraRepository(api)),
      Provider.value(value: ContabilidadRepository(api)),
      Provider.value(value: PanelRepository(api)),
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
        _metodoLogin = 'TOTP';
        await _montar(tester, tamano, const SegundoFactorScreen(), sesion: _Sesion.segundoFactor);
        expect(find.text('Verificación en dos pasos'), findsOneWidget);
        expect(find.textContaining('Google Authenticator'), findsWidgets);
      });

      testWidgets('configurar Google Authenticator en el primer ingreso', (tester) async {
        _metodoLogin = 'CONFIGURAR';
        await _montar(tester, tamano, const SegundoFactorScreen(), sesion: _Sesion.segundoFactor);
        expect(find.text('Configura la verificación en dos pasos'), findsOneWidget);
        expect(find.byKey(const Key('qr-totp')), findsOneWidget);
        expect(find.text('Activar y entrar'), findsOneWidget);
      });

      testWidgets('códigos de respaldo tras configurar', (tester) async {
        await _montar(tester, tamano,
            CodigosRespaldoNuevosScreen(codigos: List.generate(10, (i) => 'ABCDE-FGH${i}J')));
        expect(find.text('Continuar'), findsOneWidget);
      });

      testWidgets('recuperar contraseña', (tester) async {
        await _montar(tester, tamano, const RecuperarPasswordScreen(), sesion: _Sesion.anonima);
        expect(find.text('Enviar enlace'), findsOneWidget);
      });

      testWidgets('restablecer contraseña', (tester) async {
        await _montar(tester, tamano, RestablecerPasswordScreen(token: 't', alTerminar: () {}), sesion: _Sesion.anonima);
        expect(find.text('Guardar contraseña'), findsOneWidget);
      });

      testWidgets('invitación: crear la primera contraseña', (tester) async {
        await _montar(tester, tamano, RestablecerPasswordScreen(token: 't', esInvitacion: true, alTerminar: () {}),
            sesion: _Sesion.anonima);
        expect(find.text('Bienvenido: crea tu contraseña'), findsOneWidget);
      });

      testWidgets('catálogo', (tester) async {
        await _montar(tester, tamano, const CatalogScreen());
        expect(find.text('Teclado mecánico'), findsOneWidget);
      });

      testWidgets('carrito', (tester) async {
        await _montar(tester, tamano, const CartScreen());
        expect(find.text('Confirmar y facturar'), findsOneWidget);
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

      testWidgets('usuarios', (tester) async {
        await _montar(tester, tamano, const UsuariosScreen());
        expect(find.text('Usuarios'), findsWidgets);
        expect(find.textContaining('José Alejandro'), findsOneWidget);
        expect(find.text('Invitación pendiente'), findsOneWidget);
      });

      testWidgets('formulario de usuario', (tester) async {
        await _montar(tester, tamano, const Scaffold(body: UsuarioFormDialog()));
        expect(find.text('Nuevo usuario'), findsOneWidget);
        expect(find.text('+502 '), findsOneWidget);
      });
      testWidgets('bitácora de accesos', (tester) async {
        await _montar(tester, tamano, const BitacoraScreen());
        expect(find.text('Bitácora de accesos'), findsOneWidget);
      });

      // ---------- ERP ----------

      testWidgets('panel de inicio', (tester) async {
        await _montar(tester, tamano, const PanelScreen());
        expect(find.text('Ventas de hoy'), findsOneWidget);
        expect(find.text('Productos por reabastecer'), findsOneWidget);
      });

      testWidgets('clientes', (tester) async {
        await _montar(tester, tamano, const ClientesScreen());
        expect(find.text('Consumidor Final'), findsOneWidget);
      });

      testWidgets('formulario de cliente', (tester) async {
        await _montar(tester, tamano,
            Scaffold(body: TerceroFormDialog<Cliente>.cliente(guardar: (_) async => throw UnimplementedError())));
        expect(find.text('Nuevo cliente'), findsOneWidget);
      });

      testWidgets('ventas', (tester) async {
        await _montar(tester, tamano, const VentasScreen());
        expect(find.textContaining('A-1001'), findsWidgets);
      });

      testWidgets('factura de una venta', (tester) async {
        await _montar(tester, tamano, const VentaDetalleScreen(numero: 1234));
        expect(find.byKey(const Key('total-pedido')), findsOneWidget);
        expect(find.text('IVA 12 %'), findsOneWidget);
      });

      testWidgets('inventario', (tester) async {
        await _montar(tester, tamano, const InventarioScreen());
        expect(find.textContaining('reabastecer'), findsWidgets);
      });

      testWidgets('kardex', (tester) async {
        await _montar(tester, tamano, const KardexScreen(productoId: 3));
        expect(find.textContaining('Compra'), findsWidgets);
      });

      testWidgets('ajuste de inventario', (tester) async {
        await _montar(tester, tamano,
            Scaffold(body: AjusteDialog(producto: ProductoInventario.fromJson(_productoInv(1)))));
        expect(find.text('Registrar ajuste'), findsOneWidget);
      });

      testWidgets('proveedores', (tester) async {
        await _montar(tester, tamano, const ProveedoresScreen());
        expect(find.textContaining('3344556-7'), findsWidgets);
      });

      testWidgets('órdenes de compra', (tester) async {
        await _montar(tester, tamano, const OrdenesScreen());
        expect(find.text('Pendiente'), findsWidgets);
      });

      testWidgets('detalle de orden de compra', (tester) async {
        await _montar(tester, tamano, const OrdenDetalleScreen(numero: 7));
        expect(find.text('Recibir mercadería'), findsOneWidget);
      });

      testWidgets('nueva orden de compra', (tester) async {
        await _montar(tester, tamano, const NuevaOrdenScreen());
        expect(find.text('Crear orden'), findsOneWidget);
      });

      testWidgets('libro diario', (tester) async {
        await _montar(tester, tamano, const LibroDiarioScreen());
        expect(find.text('Sumas iguales'), findsWidgets);
      });

      testWidgets('nueva partida', (tester) async {
        await _montar(tester, tamano, const NuevaPartidaScreen());
        expect(find.text('Registrar partida'), findsOneWidget);
      });

      testWidgets('catálogo de cuentas y libro mayor', (tester) async {
        await _montar(tester, tamano, const CuentasScreen());
        expect(find.textContaining('Bancos'), findsWidgets);
        await _montar(tester, tamano, LibroMayorScreen(cuenta: CuentaContable.fromJson(_cuentas[0])));
        expect(find.text('Saldo final'), findsOneWidget);
      });

      testWidgets('estados financieros', (tester) async {
        await _montar(tester, tamano, const ReportesScreen());
        expect(find.textContaining('Pérdida neta'), findsOneWidget);
        for (final (pestana, esperado) in [('Balance general', 'ACTIVO'), ('Comprobación', 'Bancos con un nombre')]) {
          await tester.ensureVisible(find.text(pestana));
          await tester.pumpAndSettle();
          await tester.tap(find.text(pestana));
          await tester.pumpAndSettle();
          expect(find.textContaining(esperado), findsWidgets);
        }
      });
    });
  }
}
