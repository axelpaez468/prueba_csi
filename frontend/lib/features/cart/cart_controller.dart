import 'dart:math';

import 'package:flutter/foundation.dart';

import '../../core/network/api_exception.dart';
import '../../data/models/erp.dart';
import '../../data/models/pedido.dart';
import '../../data/models/producto.dart';
import '../../data/repositories/pedido_repository.dart';

@immutable
class CartItem {
  const CartItem(this.producto, this.cantidad);

  final Producto producto;
  final int cantidad;

  /// Solo orientativo: el importe real lo calcula el servidor al confirmar.
  double get subtotalReferencial => producto.precio * cantidad;
}

class CartController extends ChangeNotifier {
  CartController(this._pedidos);

  final PedidoRepository _pedidos;

  // Map con orden de inserción: las líneas se muestran en el orden en que se agregaron.
  final Map<int, CartItem> _items = {};
  bool _enviando = false;
  String? _error;

  /// null: consumidor final (CF), el cliente por defecto de la factura.
  Cliente? _cliente;
  String _formaPago = 'EFECTIVO';

  // Entrega de la venta.
  String _direccion = '';
  String? _departamento;
  String? _municipio;

  List<CartItem> get items => List.unmodifiable(_items.values);
  bool get vacio => _items.isEmpty;
  bool get enviando => _enviando;
  String? get error => _error;
  Cliente? get cliente => _cliente;
  String get formaPago => _formaPago;

  void elegirCliente(Cliente? cliente) {
    _cliente = cliente;
    notifyListeners();
  }

  void elegirFormaPago(String forma) {
    _formaPago = forma;
    notifyListeners();
  }

  String get direccionEntrega => _direccion;
  String? get departamento => _departamento;
  String? get municipio => _municipio;

  /// Para facturar hacen falta la dirección, el departamento y el municipio.
  bool get entregaCompleta => _direccion.trim().length >= 5 && _departamento != null && _municipio != null;

  void elegirDireccion(String direccion) {
    _direccion = direccion;
    notifyListeners();
  }

  void elegirDepartamento(String? departamento) {
    if (departamento == _departamento) return;
    _departamento = departamento;
    _municipio = null; // el municipio anterior ya no corresponde al nuevo departamento
    notifyListeners();
  }

  void elegirMunicipio(String? municipio) {
    _municipio = municipio;
    notifyListeners();
  }

  void _limpiarVenta() {
    _cliente = null;
    _formaPago = 'EFECTIVO';
    _direccion = '';
    _departamento = null;
    _municipio = null;
  }

  int get totalUnidades => _items.values.fold(0, (s, i) => s + i.cantidad);

  double get subtotalReferencial => _items.values.fold(0.0, (s, i) => s + i.subtotalReferencial);

  int cantidadDe(int productoId) => _items[productoId]?.cantidad ?? 0;

  /// Agrega sumando a lo que ya hubiera. El tope por stock es solo para guiar al usuario;
  /// la validación real de stock ocurre en el servidor.
  void agregar(Producto producto, int cantidad) {
    if (cantidad <= 0 || !producto.disponible) return;
    final nueva = min(cantidadDe(producto.id) + cantidad, producto.stock);
    _items[producto.id] = CartItem(producto, nueva);
    _error = null;
    notifyListeners();
  }

  void cambiarCantidad(int productoId, int cantidad) {
    final item = _items[productoId];
    if (item == null) return;
    if (cantidad <= 0) {
      eliminar(productoId);
      return;
    }
    _items[productoId] = CartItem(item.producto, min(cantidad, item.producto.stock));
    _error = null;
    notifyListeners();
  }

  void eliminar(int productoId) {
    if (_items.remove(productoId) == null) return;
    _error = null;
    notifyListeners();
  }

  void vaciar() {
    _items.clear();
    _error = null;
    _limpiarVenta();
    notifyListeners();
  }

  /// Devuelve el pedido creado, o null si falló (el motivo queda en [error]).
  /// Mientras hay un envío en curso, las llamadas adicionales se ignoran (evita doble clic).
  Future<Pedido?> confirmar() async {
    if (_enviando || _items.isEmpty) return null;
    _enviando = true;
    _error = null;
    notifyListeners();

    try {
      final pedido = await _pedidos.crear(
        _items.values.map((i) => LineaPedido(productoId: i.producto.id, cantidad: i.cantidad)).toList(),
        clienteId: _cliente?.id,
        formaPago: _formaPago,
        direccionEntrega: _direccion.trim().isEmpty ? null : _direccion.trim(),
        departamento: _departamento,
        municipio: _municipio,
      );
      _items.clear();
      _limpiarVenta();
      return pedido;
    } on UnauthorizedException {
      return null; // La sesión se cierra y la app vuelve al login.
    } on ApiException catch (e) {
      _error = e.message;
      return null;
    } finally {
      _enviando = false;
      notifyListeners();
    }
  }
}
