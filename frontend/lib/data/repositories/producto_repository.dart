import '../../core/network/api_client.dart';
import '../models/producto.dart';

class ProductoRepository {
  ProductoRepository(this._api);

  final ApiClient _api;

  Future<List<Producto>> listar() async {
    final json = await _api.get('/api/productos') as List;
    return json.map((p) => Producto.fromJson(p as Map<String, dynamic>)).toList();
  }

  Future<ProductoDetalle> detalle(int id) async =>
      ProductoDetalle.fromJson(await _api.get('/api/productos/$id') as Map<String, dynamic>);
}
