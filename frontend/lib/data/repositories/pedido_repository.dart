import '../../core/network/api_client.dart';
import '../../core/util/formatters.dart';
import '../models/erp.dart';
import '../models/pedido.dart';

class PedidoRepository {
  PedidoRepository(this._api);

  final ApiClient _api;

  /// Envía solo productos, cantidades, cliente y forma de pago. La venta devuelta trae el total calculado
  /// por el servidor. Sin cliente, el servidor factura a consumidor final (CF).
  Future<Pedido> crear(List<LineaPedido> lineas, {int? clienteId, String? formaPago}) async {
    final json = await _api.post('/api/pedidos', {
      'lineas': lineas.map((l) => l.toJson()).toList(),
      'clienteId': ?clienteId,
      'formaPago': ?formaPago,
    });
    return Pedido.fromJson(json as Map<String, dynamic>);
  }

  Future<Pedido> obtener(int numero) async =>
      Pedido.fromJson(await _api.get('/api/pedidos/$numero') as Map<String, dynamic>);

  Future<List<VentaResumen>> listar(DateTime desde, DateTime hasta) async {
    final json = await _api.get('/api/pedidos?desde=${fechaIso(desde)}&hasta=${fechaIso(hasta)}') as List;
    return json.map((e) => VentaResumen.fromJson(e as Map<String, dynamic>)).toList();
  }
}
