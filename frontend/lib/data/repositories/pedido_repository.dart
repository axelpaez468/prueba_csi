import '../../core/network/api_client.dart';
import '../models/pedido.dart';

class PedidoRepository {
  PedidoRepository(this._api);

  final ApiClient _api;

  /// Envía solo productoId y cantidad. El pedido devuelto trae el total calculado por el servidor.
  Future<Pedido> crear(List<LineaPedido> lineas) async {
    final json = await _api.post('/api/pedidos', {
      'lineas': lineas.map((l) => l.toJson()).toList(),
    });
    return Pedido.fromJson(json as Map<String, dynamic>);
  }
}
