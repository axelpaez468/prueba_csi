import 'package:flutter/foundation.dart';

import '../../core/network/api_client.dart';
import '../../core/network/api_exception.dart';
import '../../data/models/producto.dart';
import '../../data/repositories/producto_repository.dart';

class CatalogController extends ChangeNotifier {
  CatalogController(this._productos);

  final ProductoRepository _productos;

  List<Producto> _items = const [];
  bool _cargando = false;
  String? _error;

  List<Producto> get items => _items;
  bool get cargando => _cargando;
  String? get error => _error;

  Future<void> cargar() async {
    if (_cargando) return;
    _cargando = true;
    _error = null;
    notifyListeners();

    try {
      _items = await _productos.listar();
    } on UnauthorizedException {
      // El ApiClient ya cerró la sesión; la app vuelve al login.
    } on ApiException catch (e) {
      _error = e.message;
    } on TypeError {
      _error = ApiClient.respuestaInesperada;
    } finally {
      _cargando = false;
      notifyListeners();
    }
  }

  void limpiar() {
    _items = const [];
    _error = null;
    notifyListeners();
  }
}
