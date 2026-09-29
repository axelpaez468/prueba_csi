import 'package:flutter/material.dart';

import '../../core/util/formatters.dart';
import '../../data/models/producto.dart';

/// Fila del catálogo con selector de cantidad. Sin stock se muestra deshabilitada.
class ProductoTile extends StatefulWidget {
  const ProductoTile({
    super.key,
    required this.producto,
    required this.enCarrito,
    required this.onAgregar,
  });

  final Producto producto;
  final int enCarrito;
  final void Function(int cantidad) onAgregar;

  @override
  State<ProductoTile> createState() => _ProductoTileState();
}

class _ProductoTileState extends State<ProductoTile> {
  int _cantidad = 1;

  int get _maximo => widget.producto.stock - widget.enCarrito;

  @override
  Widget build(BuildContext context) {
    final p = widget.producto;
    final theme = Theme.of(context);
    final habilitado = p.disponible && _maximo > 0;
    final cantidad = _cantidad.clamp(1, _maximo < 1 ? 1 : _maximo);

    return Opacity(
      opacity: p.disponible ? 1 : 0.5,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 16,
            runSpacing: 8,
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 220),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(p.nombre, style: theme.textTheme.titleMedium),
                    Text('${p.codigo} · ${formatearMoneda(p.precio)}', style: theme.textTheme.bodyMedium),
                    Text(
                      p.disponible ? 'Stock: ${p.stock}' : 'Sin stock',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: p.disponible ? null : theme.colorScheme.error,
                        fontWeight: p.disponible ? null : FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: 'Menos',
                    onPressed: habilitado && cantidad > 1 ? () => setState(() => _cantidad = cantidad - 1) : null,
                    icon: const Icon(Icons.remove),
                  ),
                  SizedBox(
                    width: 32,
                    child: Text('$cantidad', textAlign: TextAlign.center, style: theme.textTheme.titleMedium),
                  ),
                  IconButton(
                    tooltip: 'Más',
                    onPressed: habilitado && cantidad < _maximo ? () => setState(() => _cantidad = cantidad + 1) : null,
                    icon: const Icon(Icons.add),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: habilitado
                        ? () {
                            widget.onAgregar(cantidad);
                            setState(() => _cantidad = 1);
                          }
                        : null,
                    icon: const Icon(Icons.add_shopping_cart),
                    label: Text(!p.disponible
                        ? 'Sin stock'
                        : _maximo > 0
                            ? 'Agregar'
                            : 'Todo en carrito'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
