import 'package:flutter/material.dart';

import '../../core/security/permisos.dart';
import '../../core/security/session.dart';
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
import '../usuarios/usuarios_screen.dart';
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

final modulos = <Modulo>[
  Modulo('Inicio', 'Indicadores del negocio', Icons.dashboard_outlined, 'General', () => const PanelScreen(), (s) => s.vePanel),
  Modulo('Catálogo', 'Productos para vender', Icons.storefront_outlined, 'Ventas', () => const CatalogScreen(), (s) => s.veCatalogo),
  Modulo('Ventas', 'Facturas emitidas', Icons.receipt_long_outlined, 'Ventas', () => const VentasScreen(), (s) => s.consultaVentas),
  Modulo('Clientes', 'NIT y datos de facturación', Icons.people_alt_outlined, 'Ventas', () => const ClientesScreen(),
      (s) => s.gestionaClientes),
  Modulo('Inventario', 'Existencias, costos y kardex', Icons.inventory_2_outlined, 'Inventario', () => const InventarioScreen(),
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
  Modulo('Usuarios', 'Altas, roles y accesos', Icons.group_outlined, 'Administración', () => const UsuariosScreen(),
      (s) => s.esAdmin),
  Modulo('Bitácora de accesos', 'Auditoría de inicios de sesión', Icons.manage_search, 'Administración',
      () => const BitacoraScreen(), (s) => s.esAdmin),
];

List<Modulo> modulosDe(Session s) => modulos.where((m) => m.visible(s)).toList();

/// Pantalla de inicio según el rol.
Widget inicioDe(Session s) => s.vePanel ? const PanelScreen() : const CatalogScreen();

void abrirModulo(BuildContext context, Modulo m) =>
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => m.pantalla()));
