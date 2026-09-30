import '../../core/network/api_client.dart';
import '../../core/util/formatters.dart';
import '../models/erp.dart';

String _q(String? texto) =>
    (texto == null || texto.trim().isEmpty) ? '' : Uri.encodeQueryComponent(texto.trim());

List<T> _lista<T>(Object? json, T Function(Map<String, dynamic>) de) =>
    (json as List).map((e) => de(e as Map<String, dynamic>)).toList();

class ClienteRepository {
  ClienteRepository(this._api);

  final ApiClient _api;

  Future<List<Cliente>> listar({String? buscar, bool inactivos = false}) async =>
      _lista(await _api.get('/api/clientes?buscar=${_q(buscar)}&inactivos=$inactivos'), Cliente.fromJson);

  Future<Cliente> guardar(int? id, Map<String, dynamic> datos) async => Cliente.fromJson(
      (id == null ? await _api.post('/api/clientes', datos) : await _api.put('/api/clientes/$id', datos))
          as Map<String, dynamic>);
}

class InventarioRepository {
  InventarioRepository(this._api);

  final ApiClient _api;

  static const _base = '/api/inventario';

  Future<List<ProductoInventario>> listar({String? buscar, bool bajoMinimo = false}) async =>
      _lista(await _api.get('$_base/productos?buscar=${_q(buscar)}&bajoMinimo=$bajoMinimo'), ProductoInventario.fromJson);

  Future<ProductoInventario> guardar(int? id, Map<String, dynamic> datos) async => ProductoInventario.fromJson(
      (id == null ? await _api.post('$_base/productos', datos) : await _api.put('$_base/productos/$id', datos))
          as Map<String, dynamic>);

  Future<Kardex> kardex(int productoId) async =>
      Kardex.fromJson(await _api.get('$_base/productos/$productoId/kardex') as Map<String, dynamic>);

  Future<MovimientoInventario> ajustar(Map<String, dynamic> datos) async =>
      MovimientoInventario.fromJson(await _api.post('$_base/ajustes', datos) as Map<String, dynamic>);
}

class CompraRepository {
  CompraRepository(this._api);

  final ApiClient _api;

  static const _base = '/api/compras';

  Future<List<Proveedor>> proveedores({String? buscar, bool inactivos = false}) async =>
      _lista(await _api.get('$_base/proveedores?buscar=${_q(buscar)}&inactivos=$inactivos'), Proveedor.fromJson);

  Future<Proveedor> guardarProveedor(int? id, Map<String, dynamic> datos) async => Proveedor.fromJson(
      (id == null ? await _api.post('$_base/proveedores', datos) : await _api.put('$_base/proveedores/$id', datos))
          as Map<String, dynamic>);

  Future<List<OrdenResumen>> ordenes({String? estado}) async =>
      _lista(await _api.get('$_base/ordenes?estado=${_q(estado)}'), OrdenResumen.fromJson);

  Future<OrdenCompra> orden(int numero) async =>
      OrdenCompra.fromJson(await _api.get('$_base/ordenes/$numero') as Map<String, dynamic>);

  Future<OrdenCompra> crearOrden(Map<String, dynamic> datos) async =>
      OrdenCompra.fromJson(await _api.post('$_base/ordenes', datos) as Map<String, dynamic>);

  Future<OrdenCompra> recibir(int numero, String facturaProveedor) async => OrdenCompra.fromJson(
      await _api.post('$_base/ordenes/$numero/recibir', {'facturaProveedor': facturaProveedor}) as Map<String, dynamic>);

  Future<OrdenCompra> anular(int numero) async =>
      OrdenCompra.fromJson(await _api.post('$_base/ordenes/$numero/anular', const <String, dynamic>{}) as Map<String, dynamic>);
}

class ContabilidadRepository {
  ContabilidadRepository(this._api);

  final ApiClient _api;

  static const _base = '/api/contabilidad';

  static String _rango(DateTime desde, DateTime hasta) => 'desde=${fechaIso(desde)}&hasta=${fechaIso(hasta)}';

  Future<List<CuentaContable>> cuentas() async => _lista(await _api.get('$_base/cuentas'), CuentaContable.fromJson);

  Future<CuentaContable> guardarCuenta(int? id, Map<String, dynamic> datos) async => CuentaContable.fromJson(
      (id == null ? await _api.post('$_base/cuentas', datos) : await _api.put('$_base/cuentas/$id', datos))
          as Map<String, dynamic>);

  Future<List<Partida>> libroDiario(DateTime desde, DateTime hasta, {String? origen}) async =>
      _lista(await _api.get('$_base/partidas?${_rango(desde, hasta)}&origen=${_q(origen)}'), Partida.fromJson);

  Future<Partida> crearPartida(Map<String, dynamic> datos) async =>
      Partida.fromJson(await _api.post('$_base/partidas', datos) as Map<String, dynamic>);

  Future<LibroMayor> mayor(int cuentaId, DateTime desde, DateTime hasta) async =>
      LibroMayor.fromJson(await _api.get('$_base/reportes/mayor/$cuentaId?${_rango(desde, hasta)}') as Map<String, dynamic>);

  Future<BalanceComprobacion> balanceComprobacion(DateTime desde, DateTime hasta) async => BalanceComprobacion.fromJson(
      await _api.get('$_base/reportes/balance-comprobacion?${_rango(desde, hasta)}') as Map<String, dynamic>);

  Future<EstadoResultados> estadoResultados(DateTime desde, DateTime hasta) async => EstadoResultados.fromJson(
      await _api.get('$_base/reportes/estado-resultados?${_rango(desde, hasta)}') as Map<String, dynamic>);

  Future<BalanceGeneral> balanceGeneral(DateTime al) async =>
      BalanceGeneral.fromJson(await _api.get('$_base/reportes/balance-general?al=${fechaIso(al)}') as Map<String, dynamic>);
}

class PanelRepository {
  PanelRepository(this._api);

  final ApiClient _api;

  Future<Panel> resumen() async => Panel.fromJson(await _api.get('/api/panel') as Map<String, dynamic>);
}

class ReporteRepository {
  ReporteRepository(this._api);

  final ApiClient _api;

  Future<ReporteVentas> ventas(DateTime desde, DateTime hasta) async => ReporteVentas.fromJson(
      await _api.get('/api/reportes/ventas?desde=${fechaIso(desde)}&hasta=${fechaIso(hasta)}') as Map<String, dynamic>);
}
