import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/util/formatters.dart';
import '../../core/widgets/app_shell.dart';
import '../../data/models/producto.dart';
import 'producto_imagen.dart';

/// Tarjeta de producto del catálogo con selector de cantidad. Sin stock se muestra deshabilitada.
class ProductoTile extends StatefulWidget {
  const ProductoTile({
    super.key,
    required this.producto,
    required this.enCarrito,
    required this.onAgregar,
    this.onVerDetalle,
  });

  final Producto producto;
  final int enCarrito;
  final void Function(int cantidad) onAgregar;

  /// Abre la ficha del producto (tocar la foto o el nombre).
  final VoidCallback? onVerDetalle;

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

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Opacity(
        opacity: p.disponible ? 1 : 0.6,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InkWell(onTap: widget.onVerDetalle, child: _Portada(producto: p)),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(p.codigo,
                        style: theme.textTheme.labelSmall?.copyWith(
                            color: AppColors.textSecondary, letterSpacing: 0.6)),
                    const SizedBox(height: 2),
                    InkWell(
                      onTap: widget.onVerDetalle,
                      child: Text(p.nombre, maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleMedium),
                    ),
                    if (p.marca != null || p.categoria != null)
                      Text([?p.marca, ?p.categoria].join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(color: AppColors.textSecondary)),
                    const SizedBox(height: 8),
                    // Wrap: si no cabe en una línea, la etiqueta baja; el precio nunca se parte.
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(formatearMoneda(p.precio),
                            softWrap: false,
                            style: theme.textTheme.titleLarge?.copyWith(color: AppColors.primary)),
                        _PillStock(stock: p.stock),
                      ],
                    ),
                    if (widget.enCarrito > 0) ...[
                      const SizedBox(height: 6),
                      Text('${widget.enCarrito} en tu carrito',
                          style: theme.textTheme.bodySmall?.copyWith(color: AppColors.accent)),
                    ],
                    if (widget.onVerDetalle != null)
                      TextButton(
                        style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(0, 32)),
                        onPressed: widget.onVerDetalle,
                        child: const Text('Ver detalle y especificaciones'),
                      ),
                    const SizedBox(height: 6),
                    const Spacer(),
                    Row(
                      children: [
                        _Selector(
                          cantidad: cantidad,
                          onMenos: habilitado && cantidad > 1 ? () => setState(() => _cantidad = cantidad - 1) : null,
                          onMas: habilitado && cantidad < _maximo ? () => setState(() => _cantidad = cantidad + 1) : null,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: habilitado
                                ? () {
                                    widget.onAgregar(cantidad);
                                    setState(() => _cantidad = 1);
                                  }
                                : null,
                            icon: const Icon(Icons.add_shopping_cart, size: 18),
                            label: Text(!p.disponible
                                ? 'Sin stock'
                                : _maximo > 0
                                    ? 'Agregar'
                                    : 'Máximo'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Foto del producto en la parte superior de la tarjeta, con etiqueta "Agotado" si no hay stock.
class _Portada extends StatelessWidget {
  const _Portada({required this.producto});

  final Producto producto;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 160,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ProductoImagen(producto: producto),
          if (!producto.disponible)
            Positioned(
              top: 10,
              left: 10,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.textPrimary.withValues(alpha: 0.8),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: const Text('Agotado',
                    style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
              ),
            ),
        ],
      ),
    );
  }
}

class _PillStock extends StatelessWidget {
  const _PillStock({required this.stock});

  final int stock;

  @override
  Widget build(BuildContext context) {
    if (stock <= 0) {
      return const StatusPill(texto: 'Sin stock', color: AppColors.danger, fondo: AppColors.dangerBg);
    }
    if (stock <= 3) {
      return StatusPill(
          texto: stock == 1 ? 'Última unidad' : 'Quedan $stock',
          color: AppColors.warning,
          fondo: AppColors.warningBg);
    }
    return StatusPill(texto: '$stock disponibles', color: AppColors.success, fondo: AppColors.successBg);
  }
}

class _Selector extends StatelessWidget {
  const _Selector({required this.cantidad, required this.onMenos, required this.onMas});

  final int cantidad;
  final VoidCallback? onMenos;
  final VoidCallback? onMas;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 44,
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'Menos',
            visualDensity: VisualDensity.compact,
            onPressed: onMenos,
            icon: const Icon(Icons.remove, size: 18),
          ),
          SizedBox(
            width: 22,
            child: Text('$cantidad',
                textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleSmall),
          ),
          IconButton(
            tooltip: 'Más',
            visualDensity: VisualDensity.compact,
            onPressed: onMas,
            icon: const Icon(Icons.add, size: 18),
          ),
        ],
      ),
    );
  }
}
