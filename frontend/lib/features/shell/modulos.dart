import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/security/permisos.dart';
import '../../core/security/session.dart';
import '../auth/session_controller.dart';
import '../catalog/catalog_screen.dart';
import '../clientes/clientes_screen.dart';
import '../compras/ordenes_screen.dart';
import '../compras/proveedores_screen.dart';
import '../contabilidad/cuentas_screen.dart';
import '../contabilidad/libro_diario_screen.dart';
import '../contabilidad/reportes_screen.dart';
import '../cuenta/bitacora_screen.dart';
import '../inventario/inventario_screen.dart';
import '../panel/panel_screen.dart';
import '../productos/productos_screen.dart';
import '../reportes/pronostico_screen.dart';
import '../usuarios/usuarios_screen.dart';
import '../ventas/pipeline_screen.dart';
import '../ventas/reporte_ventas_screen.dart';
import '../ventas/ventas_screen.dart';

/// Módulo del ERP: dónde está y quién puede verlo.
class Modulo {
  const Modulo(this.titulo, this.descripcion, this.icono, this.grupo, this.pantalla, this.visible);

  final String titulo;
  final String descripcion;
  final IconData icono;
  final String grupo;
  final Widget Function() pantalla;
  final bool Function(Session s) visible;
}

/// Área del ERP en la barra de navegación, en el orden en que se muestran.
class Grupo {
  const Grupo(this.nombre, this.icono);

  final String nombre;
  final IconData icono;
}

const grupos = <Grupo>[
  Grupo('Inicio', Icons.space_dashboard_outlined),
  Grupo('Ventas', Icons.point_of_sale_outlined),
  Grupo('Inventario', Icons.inventory_2_outlined),
  Grupo('Compras', Icons.local_shipping_outlined),
  Grupo('Contabilidad', Icons.account_balance_outlined),
  Grupo('Reportes', Icons.insights_outlined),
  Grupo('Administración', Icons.admin_panel_settings_outlined),
];

final modulos = <Modulo>[
  Modulo('Panel', 'Indicadores del negocio', Icons.space_dashboard_outlined, 'Inicio', () => const PanelScreen(), (s) => s.vePanel),
  Modulo('Catálogo', 'Productos para vender', Icons.storefront_outlined, 'Ventas', () => const CatalogScreen(), (s) => s.veCatalogo),
  Modulo('Ventas', 'Facturas emitidas', Icons.receipt_long_outlined, 'Ventas', () => const VentasScreen(), (s) => s.consultaVentas),
  Modulo('Pipeline', 'Etapas: revisión, autorización y entrega', Icons.view_kanban_outlined, 'Ventas',
      () => const PipelineScreen(), (s) => s.vePipeline),
  Modulo('Clientes', 'NIT y datos de facturación', Icons.people_alt_outlined, 'Ventas', () => const ClientesScreen(),
      (s) => s.gestionaClientes),
  Modulo('Productos', 'Alta, ficha, fotos y baja', Icons.category_outlined, 'Inventario', () => const ProductosScreen(),
      (s) => s.gestionaInventario),
  Modulo('Existencias', 'Costos, kardex y ajustes', Icons.inventory_2_outlined, 'Inventario', () => const InventarioScreen(),
      (s) => s.consultaInventario),
  Modulo('Órdenes de compra', 'Pedidos a proveedores y recepción', Icons.local_shipping_outlined, 'Compras',
      () => const OrdenesScreen(), (s) => s.consultaCompras),
  Modulo('Proveedores', 'Datos de proveedores', Icons.store_mall_directory_outlined, 'Compras', () => const ProveedoresScreen(),
      (s) => s.consultaCompras),
  Modulo('Libro diario', 'Partidas contables', Icons.menu_book_outlined, 'Contabilidad', () => const LibroDiarioScreen(),
      (s) => s.llevaContabilidad),
  Modulo('Catálogo de cuentas', 'Cuentas, saldos y libro mayor', Icons.account_tree_outlined, 'Contabilidad',
      () => const CuentasScreen(), (s) => s.llevaContabilidad),
  Modulo('Estados financieros', 'Balance y estado de resultados', Icons.assessment_outlined, 'Contabilidad',
      () => const ReportesScreen(), (s) => s.llevaContabilidad),
  Modulo('Reportes de ventas', 'Por día, producto, vendedor y cliente', Icons.bar_chart_outlined, 'Reportes',
      () => const ReporteVentasScreen(), (s) => s.consultaVentas),
  Modulo('Pipeline y pronóstico', 'Forecast según la probabilidad de cierre de cada etapa', Icons.trending_up, 'Reportes',
      () => const PronosticoScreen(), (s) => s.consultaVentas),
  Modulo('Usuarios', 'Altas, roles y accesos', Icons.group_outlined, 'Administración', () => const UsuariosScreen(),
      (s) => s.esAdmin),
  Modulo('Bitácora de accesos', 'Auditoría de inicios de sesión', Icons.manage_search, 'Administración',
      () => const BitacoraScreen(), (s) => s.esAdmin),
];

List<Modulo> modulosDe(Session s) => modulos.where((m) => m.visible(s)).toList();

/// Áreas con al menos un módulo visible para el rol, con sus módulos.
List<(Grupo, List<Modulo>)> gruposDe(Session s) {
  final visibles = modulosDe(s);
  return [
    for (final g in grupos)
      if (visibles.any((m) => m.grupo == g.nombre)) (g, visibles.where((m) => m.grupo == g.nombre).toList()),
  ];
}

/// Pantalla de inicio según el rol.
Widget inicioDe(Session s) => s.vePanel ? const PanelScreen() : const CatalogScreen();

/// Módulo de inicio del rol (el que se resalta cuando se está en la primera pantalla).
Modulo inicioModuloDe(Session s) => modulos.firstWhere((m) => m.titulo == (s.vePanel ? 'Panel' : 'Catálogo'));

/// Qué módulo está abierto, para resaltarlo en la barra de navegación y mostrar el área en el encabezado.
class NavegacionController extends ChangeNotifier {
  Modulo? _actual;

  /// null: la pantalla de inicio del rol.
  Modulo? get actual => _actual;

  void _cambiar(Modulo? m) {
    if (_actual == m) return;
    _actual = m;
    notifyListeners();
  }

  void reiniciar() => _cambiar(null);
}

/// Módulo que se considera abierto: el elegido en la barra o, si no hay, el de inicio del rol.
Modulo? moduloActual(BuildContext context) {
  final actual = context.watch<NavegacionController?>()?.actual;
  final session = context.watch<SessionController?>()?.session;
  return actual ?? (session == null ? null : inicioModuloDe(session));
}

/// Abre un módulo desde la barra de navegación. Funciona como pestañas: reemplaza lo que estaba abierto
/// (salvo la pantalla de inicio), para que "volver" siempre lleve al inicio y no se apilen pantallas.
void abrirModulo(BuildContext context, Modulo m) {
  final nav = context.read<NavegacionController?>();
  final session = context.read<SessionController?>()?.session;
  final navigator = Navigator.of(context);
  navigator.popUntil((r) => r.isFirst);
  if (session != null && m.titulo == inicioModuloDe(session).titulo) {
    nav?._cambiar(null);
    return;
  }
  nav?._cambiar(m);
  navigator.push(MaterialPageRoute(builder: (_) => m.pantalla())).then((_) {
    // Al volver al inicio con "atrás", se quita el resaltado.
    if (nav?._actual == m) nav?._cambiar(null);
  });
}
