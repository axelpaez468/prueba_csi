import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/util/formatters.dart';
import '../auth/session_controller.dart';
import '../catalog/catalog_controller.dart';
import '../order/order_confirmation_screen.dart';
import 'cart_controller.dart';

class CartScreen extends StatelessWidget {
  const CartScreen({super.key});

  Future<void> _confirmar(BuildContext context) async {
    final carrito = context.read<CartController>();
    final catalogo = context.read<CatalogController>();
    final navigator = Navigator.of(context);

    final pedido = await carrito.confirmar();
    // Con o sin éxito el stock cambió (o alguien más compró): se refresca el catálogo.
    catalogo.cargar();
    if (pedido != null) {
      navigator.pushReplacement(MaterialPageRoute(builder: (_) => OrderConfirmationScreen(pedido: pedido)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final carrito = context.watch<CartController>();
    final esVendedor = context.watch<SessionController>().session?.esVendedor ?? false;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Carrito')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: carrito.vacio
              ? const Center(child: Text('El carrito está vacío.'))
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    for (final item in carrito.items)
                      Card(
                        child: ListTile(
                          title: Text(item.producto.nombre),
                          subtitle: Text(
                              '${formatearMoneda(item.producto.precio)} c/u · stock ${item.producto.stock}'),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                tooltip: 'Menos',
                                onPressed: carrito.enviando
                                    ? null
                                    : () => carrito.cambiarCantidad(item.producto.id, item.cantidad - 1),
                                icon: const Icon(Icons.remove),
                              ),
                              Text('${item.cantidad}', style: theme.textTheme.titleMedium),
                              IconButton(
                                tooltip: 'Más',
                                onPressed: carrito.enviando || item.cantidad >= item.producto.stock
                                    ? null
                                    : () => carrito.cambiarCantidad(item.producto.id, item.cantidad + 1),
                                icon: const Icon(Icons.add),
                              ),
                              SizedBox(
                                width: 110,
                                child: Text(formatearMoneda(item.subtotalReferencial), textAlign: TextAlign.end),
                              ),
                              IconButton(
                                tooltip: 'Eliminar',
                                onPressed: carrito.enviando ? null : () => carrito.eliminar(item.producto.id),
                                icon: const Icon(Icons.delete_outline),
                              ),
                            ],
                          ),
                        ),
                      ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Subtotal referencial', style: theme.textTheme.titleMedium),
                        Text(formatearMoneda(carrito.subtotalReferencial), style: theme.textTheme.titleLarge),
                      ],
                    ),
                    Text(
                      'Es un estimado. El total definitivo lo calcula el sistema al confirmar, con los precios vigentes.',
                      style: theme.textTheme.bodySmall,
                    ),
                    if (carrito.error != null) ...[
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.errorContainer,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(carrito.error!, style: TextStyle(color: theme.colorScheme.onErrorContainer)),
                      ),
                    ],
                    if (!esVendedor) ...[
                      const SizedBox(height: 16),
                      Text('Solo los usuarios con rol VENDEDOR pueden confirmar pedidos.',
                          style: TextStyle(color: theme.colorScheme.error)),
                    ],
                    const SizedBox(height: 24),
                    FilledButton.icon(
                      // Deshabilitado mientras se procesa: evita pedidos duplicados por doble clic.
                      onPressed: carrito.enviando || !esVendedor ? null : () => _confirmar(context),
                      icon: carrito.enviando
                          ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.check),
                      label: Text(carrito.enviando ? 'Procesando...' : 'Confirmar pedido'),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}
