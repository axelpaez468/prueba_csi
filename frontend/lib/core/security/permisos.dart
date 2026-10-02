import 'session.dart';

/// Roles del ERP y qué puede hacer cada uno. Es un espejo de backend/Domain/Roles.cs: la interfaz solo oculta
/// lo que el usuario no puede usar; quien decide de verdad es la API (responde 403).
class Roles {
  const Roles._();

  static const vendedor = 'VENDEDOR';
  static const admin = 'ADMIN';
  static const bodega = 'BODEGA';
  static const compras = 'COMPRAS';
  static const contador = 'CONTADOR';

  static const todos = [vendedor, admin, bodega, compras, contador];

  static String nombre(String rol) => switch (rol) {
        vendedor => 'Vendedor',
        admin => 'Administrador',
        bodega => 'Bodega',
        compras => 'Compras',
        contador => 'Contador',
        _ => rol,
      };

  static String descripcion(String rol) => switch (rol) {
        vendedor => 'Vende desde el catálogo y atiende clientes.',
        admin => 'Ve todos los módulos y administra usuarios.',
        bodega => 'Productos, existencias, ajustes y recepción de compras.',
        compras => 'Proveedores y órdenes de compra.',
        contador => 'Catálogo de cuentas, partidas y estados financieros.',
        _ => '',
      };
}

extension PermisosSesion on Session {
  bool _es(List<String> roles) => roles.contains(rol);

  bool get puedeVender => rol == Roles.vendedor;
  bool get veCatalogo => _es([Roles.vendedor, Roles.admin]);
  bool get gestionaClientes => _es([Roles.vendedor, Roles.admin]);
  bool get consultaVentas => _es([Roles.vendedor, Roles.admin, Roles.contador]);
  bool get gestionaInventario => _es([Roles.bodega, Roles.admin]);
  bool get consultaInventario => _es([Roles.bodega, Roles.admin, Roles.compras, Roles.contador]);
  bool get gestionaCompras => _es([Roles.compras, Roles.admin]);
  bool get recibeCompras => _es([Roles.bodega, Roles.compras, Roles.admin]);
  bool get consultaCompras => _es([Roles.bodega, Roles.compras, Roles.admin, Roles.contador]);
  bool get llevaContabilidad => _es([Roles.contador, Roles.admin]);

  /// El vendedor trabaja desde el catálogo; los demás roles empiezan en el panel de indicadores.
  bool get vePanel => _es([Roles.admin, Roles.bodega, Roles.compras, Roles.contador]);

  String get nombreRol => Roles.nombre(rol);

  /// Tablero de etapas de las ventas.
  bool get vePipeline => _es([Roles.vendedor, Roles.admin, Roles.contador, Roles.bodega]);

  /// Si el rol puede llevar una venta A esta etapa (espejo de EstadosVenta.QuienPuedeLlevarA del backend).
  bool puedeLlevarA(String etapa) => switch (etapa) {
        'REVISADO' => _es([Roles.vendedor, Roles.admin]),
        'AUTORIZADO' => _es([Roles.admin, Roles.contador]),
        'DESPACHADO' || 'EN_CAMINO' || 'ENTREGADO' => _es([Roles.bodega, Roles.admin]),
        _ => false,
      };
}
