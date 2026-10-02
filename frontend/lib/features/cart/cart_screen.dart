import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/util/formatters.dart';
import '../../core/widgets/app_shell.dart';
import '../../data/models/erp.dart';
import '../auth/session_controller.dart';
import '../catalog/catalog_controller.dart';
import '../catalog/producto_imagen.dart';
import '../clientes/clientes_screen.dart';
import '../order/order_confirmation_screen.dart';
import '../shell/app_top_bar.dart';
import 'cart_controller.dart';
import 'entrega_form.dart';

class CartScreen extends StatelessWidget {
  const CartScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final carrito = context.watch<CartController>();
    final ancho = MediaQuery.sizeOf(context).width;

    return Scaffold(
      appBar: AppTopBar(
        mostrarCarrito: false,
        leading: IconButton(
          tooltip: 'Volver al catálogo',
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const Icon(Icons.arrow_back),
        ),
      ),
      body: carrito.vacio
          ? EmptyState(
              icono: Icons.shopping_cart_outlined,
              titulo: 'Tu carrito está vacío',
              mensaje: 'Agrega productos desde el catálogo para armar un pedido.',
              accion: FilledButton.icon(
                onPressed: () => Navigator.of(context).maybePop(),
                icon: const Icon(Icons.storefront_outlined, size: 18),
                label: const Text('Ir al catálogo'),
              ),
            )
          : SingleChildScrollView(
              child: PageBody(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    PageHeader(
                      titulo: 'Carrito',
                      subtitulo:
                          '${carrito.items.length} ${carrito.items.length == 1 ? 'producto' : 'productos'} · ${carrito.totalUnidades} unidades',
                    ),
                    Padding(
                      padding: EdgeInsets.fromLTRB(ancho < Breakpoints.compacto ? 16 : 24, 0, ancho < Breakpoints.compacto ? 16 : 24, 32),
                      child: ancho >= Breakpoints.amplio
                          ? const Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(flex: 3, child: _ListaLineas()),
                                SizedBox(width: 24),
                                SizedBox(width: 360, child: _Resumen()),
                              ],
                            )
                          : const Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [_ListaLineas(), SizedBox(height: 20), _Resumen()],
                            ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}

class _ListaLineas extends StatelessWidget {
  const _ListaLineas();

  /// Por debajo de este ancho de tarjeta cada línea se apila (celular).
  static const _anchoTabla = 520.0;

  @override
  Widget build(BuildContext context) {
    final carrito = context.watch<CartController>();
    final theme = Theme.of(context);

    return Card(
      child: LayoutBuilder(builder: (context, constraints) {
        final tabla = constraints.maxWidth >= _anchoTabla;
        final margen = tabla ? 20.0 : 16.0;

        return Column(
          children: [
            if (tabla) ...[
              Padding(
                padding: EdgeInsets.fromLTRB(margen, 16, margen, 12),
                child: Row(
                  children: [
                    Expanded(child: Text('Producto', style: _encabezado(theme))),
                    SizedBox(width: 124, child: Text('Cantidad', textAlign: TextAlign.center, style: _encabezado(theme))),
                    SizedBox(width: 110, child: Text('Subtotal', textAlign: TextAlign.end, style: _encabezado(theme))),
                    const SizedBox(width: 44),
                  ],
                ),
              ),
              const Divider(),
            ] else
              const SizedBox(height: 4),
            for (final (i, item) in carrito.items.indexed) ...[
              if (i > 0) Divider(indent: margen, endIndent: margen),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: margen, vertical: 12),
                child: tabla ? _lineaTabla(context, carrito, item) : _lineaApilada(context, carrito, item),
              ),
            ],
            const SizedBox(height: 8),
          ],
        );
      }),
    );
  }

  Widget _lineaTabla(BuildContext context, CartController carrito, CartItem item) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(child: _Descripcion(item: item)),
        SizedBox(width: 124, child: _SelectorCantidad(carrito: carrito, item: item)),
        SizedBox(
          width: 110,
          child: Text(formatearMoneda(item.subtotalReferencial),
              textAlign: TextAlign.end, style: theme.textTheme.titleSmall),
        ),
        SizedBox(width: 44, child: _BotonEliminar(carrito: carrito, item: item)),
      ],
    );
  }

  Widget _lineaApilada(BuildContext context, CartController carrito, CartItem item) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _Descripcion(item: item)),
            _BotonEliminar(carrito: carrito, item: item),
          ],
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            _SelectorCantidad(carrito: carrito, item: item),
            const Spacer(),
            Text(formatearMoneda(item.subtotalReferencial), style: theme.textTheme.titleSmall),
          ],
        ),
      ],
    );
  }

  static TextStyle? _encabezado(ThemeData theme) =>
      theme.textTheme.labelMedium?.copyWith(color: AppColors.textSecondary, letterSpacing: 0.4);
}

class _Descripcion extends StatelessWidget {
  const _Descripcion({required this.item});

  final CartItem item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: SizedBox.square(dimension: 48, child: ProductoImagen(producto: item.producto, tamanoIcono: 22)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(item.producto.nombre, style: theme.textTheme.titleSmall),
              const SizedBox(height: 2),
              Text('${item.producto.codigo} · ${formatearMoneda(item.producto.precio)} c/u',
                  style: theme.textTheme.bodySmall?.copyWith(color: AppColors.textSecondary)),
            ],
          ),
        ),
      ],
    );
  }
}

class _SelectorCantidad extends StatelessWidget {
  const _SelectorCantidad({required this.carrito, required this.item});

  final CartController carrito;
  final CartItem item;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          tooltip: 'Menos',
          visualDensity: VisualDensity.compact,
          onPressed: carrito.enviando ? null : () => carrito.cambiarCantidad(item.producto.id, item.cantidad - 1),
          icon: const Icon(Icons.remove_circle_outline, size: 20),
        ),
        SizedBox(
          width: 24,
          child: Text('${item.cantidad}', textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleSmall),
        ),
        IconButton(
          tooltip: 'Más',
          visualDensity: VisualDensity.compact,
          onPressed: carrito.enviando || item.cantidad >= item.producto.stock
              ? null
              : () => carrito.cambiarCantidad(item.producto.id, item.cantidad + 1),
          icon: const Icon(Icons.add_circle_outline, size: 20),
        ),
      ],
    );
  }
}

class _BotonEliminar extends StatelessWidget {
  const _BotonEliminar({required this.carrito, required this.item});

  final CartController carrito;
  final CartItem item;

  @override
  Widget build(BuildContext context) => IconButton(
        tooltip: 'Eliminar',
        onPressed: carrito.enviando ? null : () => carrito.eliminar(item.producto.id),
        icon: const Icon(Icons.delete_outline, color: AppColors.textSecondary),
      );
}
class _Resumen extends StatelessWidget {
  const _Resumen();

  Future<void> _confirmar(BuildContext context) async {
    final carrito = context.read<CartController>();
    final catalogo = context.read<CatalogController>();
    final navigator = Navigator.of(context);
    ScaffoldMessenger.of(context).clearSnackBars();

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

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Resumen de la venta', style: theme.textTheme.titleMedium),
            const SizedBox(height: 16),
            _Fila('Productos', '${carrito.items.length}'),
            const SizedBox(height: 8),
            _Fila('Unidades', '${carrito.totalUnidades}'),
            const Padding(padding: EdgeInsets.symmetric(vertical: 14), child: Divider()),
            if (esVendedor) ...[
              const _Facturacion(),
              const Padding(padding: EdgeInsets.symmetric(vertical: 14), child: Divider()),
              const EntregaForm(),
              const Padding(padding: EdgeInsets.symmetric(vertical: 14), child: Divider()),
            ],
            Row(
              children: [
                Expanded(child: Text('Total referencial', style: theme.textTheme.titleSmall)),
                Text(formatearMoneda(carrito.subtotalReferencial),
                    style: theme.textTheme.titleLarge?.copyWith(color: AppColors.primary)),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Precios con IVA incluido. Es un estimado: el total definitivo lo calcula el sistema al confirmar, con los precios vigentes.',
              style: theme.textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
            ),
            if (carrito.error != null) ...[
              const SizedBox(height: 16),
              InlineBanner.error(carrito.error!),
            ],
            if (esVendedor && !carrito.entregaCompleta) ...[
              const SizedBox(height: 16),
              const InlineBanner.info('Completa la dirección, el departamento y el municipio de entrega para facturar.'),
            ],
            if (!esVendedor) ...[
              const SizedBox(height: 16),
              const InlineBanner.info('Solo los usuarios con rol Vendedor pueden registrar ventas.'),
            ],
            const SizedBox(height: 20),
            FilledButton.icon(
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48), backgroundColor: AppColors.accent),
              // Deshabilitado mientras se procesa: evita pedidos duplicados por doble clic.
              onPressed: carrito.enviando || !esVendedor || !carrito.entregaCompleta ? null : () => _confirmar(context),
              icon: carrito.enviando
                  ? const SizedBox.square(
                      dimension: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.check_circle_outline),
              label: Text(carrito.enviando ? 'Procesando...' : 'Confirmar y facturar'),
            ),
            const SizedBox(height: 10),
            OutlinedButton(
              onPressed: carrito.enviando ? null : () => Navigator.of(context).maybePop(),
              child: const Text('Seguir comprando'),
            ),
          ],
        ),
      ),
    );
  }
}

class _Fila extends StatelessWidget {
  const _Fila(this.etiqueta, this.valor);

  final String etiqueta;
  final String valor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(
            child: Text(etiqueta, style: theme.textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary))),
        Text(valor, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
      ],
    );
  }
}

/// Cliente (NIT) y forma de pago de la factura. La venta es siempre de contado.
class _Facturacion extends StatelessWidget {
  const _Facturacion();

  @override
  Widget build(BuildContext context) {
    final carrito = context.watch<CartController>();
    final theme = Theme.of(context);
    final cliente = carrito.cliente;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Facturar a', style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.border),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(children: [
            Icon(cliente == null ? Icons.person_outline : Icons.business_outlined, color: AppColors.textSecondary),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(cliente?.nombre ?? 'Consumidor Final',
                    key: const Key('cliente-factura'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                Text('NIT ${cliente?.nitFormateado ?? 'CF'}',
                    style: theme.textTheme.bodySmall?.copyWith(color: AppColors.textSecondary)),
              ]),
            ),
            TextButton(
              onPressed: carrito.enviando
                  ? null
                  : () async {
                      final elegido = await showDialog<Cliente>(
                          context: context, builder: (_) => const SeleccionarClienteDialog());
                      if (elegido != null) {
                        carrito.elegirCliente(elegido.esConsumidorFinal ? null : elegido);
                        if (!elegido.esConsumidorFinal && elegido.direccion != null && carrito.direccionEntrega.isEmpty) {
                          carrito.elegirDireccion(elegido.direccion!);
                        }
                      }
                    },
              child: const Text('Cambiar'),
            ),
          ]),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: carrito.formaPago,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Forma de pago (contado)', isDense: true),
          items: [
            for (final f in const ['EFECTIVO', 'TARJETA', 'TRANSFERENCIA'])
              DropdownMenuItem(value: f, child: Text(formaPagoLegible(f))),
          ],
          onChanged: carrito.enviando ? null : (v) => carrito.elegirFormaPago(v ?? 'EFECTIVO'),
        ),
      ],
    );
  }
}
