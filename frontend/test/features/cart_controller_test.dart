import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:pedidos_app/core/network/api_client.dart';
import 'package:pedidos_app/data/models/pedido.dart';
import 'package:pedidos_app/data/models/producto.dart';
import 'package:pedidos_app/data/repositories/pedido_repository.dart';
import 'package:pedidos_app/features/cart/cart_controller.dart';
import 'package:http/testing.dart';
import 'package:http/http.dart' as http;

/// Repositorio falso que deja el envío "colgado" hasta que la prueba lo complete.
class _PedidoRepositoryLento extends PedidoRepository {
  _PedidoRepositoryLento()
      : super(ApiClient(
          baseUrl: 'http://api.test',
          httpClient: MockClient((_) async => http.Response('', 500)),
          tokenProvider: () async => null,
        ));

  final completer = Completer<Pedido>();
  var llamadas = 0;

  @override
  Future<Pedido> crear(List<LineaPedido> lineas, {int? clienteId, String? formaPago}) {
    llamadas++;
    return completer.future;
  }
}

const _teclado = Producto(id: 1, codigo: 'P-001', nombre: 'Teclado', precio: 450, stock: 3);
const _mouse = Producto(id: 2, codigo: 'P-002', nombre: 'Mouse', precio: 125.5, stock: 10);

void main() {
  test('el subtotal referencial suma precio x cantidad y respeta el stock como tope', () {
    final carrito = CartController(_PedidoRepositoryLento())
      ..agregar(_teclado, 2)
      ..agregar(_teclado, 5) // tope: stock 3
      ..agregar(_mouse, 1);

    expect(carrito.cantidadDe(_teclado.id), 3);
    expect(carrito.subtotalReferencial, 3 * 450 + 125.5);

    carrito.cambiarCantidad(_teclado.id, 0);
    expect(carrito.cantidadDe(_teclado.id), 0);
    expect(carrito.items, hasLength(1));
  });

  test('un doble clic en Confirmar envía un solo pedido', () async {
    final repo = _PedidoRepositoryLento();
    final carrito = CartController(repo)..agregar(_teclado, 1);

    final primero = carrito.confirmar();
    expect(carrito.enviando, isTrue);
    final segundo = await carrito.confirmar(); // mientras el primero sigue en curso

    expect(segundo, isNull);
    expect(repo.llamadas, 1);

    repo.completer.complete(Pedido(numero: 7, fecha: DateTime.now(), total: 450, lineas: const []));
    expect((await primero)?.numero, 7);
    expect(carrito.enviando, isFalse);
    expect(carrito.vacio, isTrue);
  });
}
