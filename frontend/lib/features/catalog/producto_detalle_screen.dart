import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/security/permisos.dart';
import '../../core/theme/app_theme.dart';
import '../../core/util/formatters.dart';
import '../../core/widgets/app_shell.dart';
import '../../core/widgets/erp_widgets.dart';
import '../../data/models/producto.dart';
import '../../data/repositories/producto_repository.dart';
import '../auth/session_controller.dart';
import '../cart/cart_controller.dart';
import '../cart/cart_screen.dart';
import '../shell/app_top_bar.dart';
import 'carruseles.dart';

/// Ficha del producto: foto, precio, existencia, descripción detallada, especificaciones y garantía.
/// El vendedor puede agregarlo al carrito desde aquí.
class ProductoDetalleScreen extends StatefulWidget {
  const ProductoDetalleScreen({super.key, required this.producto});

  /// Datos del catálogo: se muestran de inmediato mientras llega la ficha completa.
  final Producto producto;

  @override
  State<ProductoDetalleScreen> createState() => _ProductoDetalleScreenState();
}

class _ProductoDetalleScreenState extends State<ProductoDetalleScreen>
    with CargaDatos<ProductoDetalleScreen, ProductoDetalle> {
  int _cantidad = 1;

  @override
  Future<ProductoDetalle> obtener() => context.read<ProductoRepository>().detalle(widget.producto.id);

  void _agregar(Producto p) {
    context.read<CartController>().agregar(p, _cantidad);
    setState(() => _cantidad = 1);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text('${p.nombre} agregado al carrito'),
        action: SnackBarAction(
          label: 'Ver carrito',
          textColor: const Color(0xFF9FE3D0),
          onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CartScreen())),
        ),
        persist: false,
      ));
  }

  @override
  Widget build(BuildContext context) {
    final detalle = datos;
    final p = detalle?.producto ?? widget.producto;
    final theme = Theme.of(context);
    final compacto = Breakpoints.esCompacto(context);
    final vende = context.watch<SessionController>().session?.puedeVender ?? false;
    final enCarrito = context.watch<CartController>().cantidadDe(p.id);
    final maximo = p.stock - enCarrito;

    // Mientras llega la ficha se muestra la foto principal; luego, la galería completa.
    final imagenes = detalle?.imagenes ?? [?p.imagenId];
    final foto = CarruselImagenes(key: ValueKey(imagenes.length), producto: p, imagenes: imagenes);

    final resumen = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(spacing: 8, runSpacing: 6, children: [
          if (p.categoria != null)
            StatusPill(texto: p.categoria!, color: AppColors.primary, fondo: const Color(0xFFE8EEF7)),
          StatusPill(texto: p.codigo, color: AppColors.textSecondary, fondo: AppColors.background),
        ]),
        const SizedBox(height: 10),
        Text(p.nombre, key: const Key('nombre-producto'), style: theme.textTheme.headlineSmall),
        if (p.marca != null) ...[
          const SizedBox(height: 4),
          Text('Marca ${p.marca}', style: theme.textTheme.titleSmall?.copyWith(color: AppColors.textSecondary)),
        ],
        const SizedBox(height: 16),
        Text(formatearMoneda(p.precio), style: theme.textTheme.headlineMedium?.copyWith(color: AppColors.primary)),
        textoSecundario(context, 'IVA incluido · precio sujeto a confirmación al facturar'),
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, children: [
          p.stock <= 0
              ? const StatusPill(texto: 'Sin existencia', color: AppColors.danger, fondo: AppColors.dangerBg)
              : StatusPill(
                  texto: '${p.stock} disponibles',
                  color: p.stock <= 3 ? AppColors.warning : AppColors.success,
                  fondo: p.stock <= 3 ? AppColors.warningBg : AppColors.successBg),
          if (detalle != null)
            StatusPill(
              texto: garantiaLegible(detalle.garantiaMeses),
              color: AppColors.textSecondary,
              fondo: AppColors.background,
              icono: Icons.verified_user_outlined,
            ),
        ]),
        if (vende) ...[
          const SizedBox(height: 20),
          Row(children: [
            IconButton.outlined(
              tooltip: 'Menos',
              onPressed: _cantidad > 1 ? () => setState(() => _cantidad--) : null,
              icon: const Icon(Icons.remove),
            ),
            SizedBox(width: 44, child: Text('$_cantidad', textAlign: TextAlign.center, style: theme.textTheme.titleMedium)),
            IconButton.outlined(
              tooltip: 'Más',
              onPressed: _cantidad < maximo ? () => setState(() => _cantidad++) : null,
              icon: const Icon(Icons.add),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton.icon(
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                onPressed: maximo > 0 && _cantidad <= maximo ? () => _agregar(p) : null,
                icon: const Icon(Icons.add_shopping_cart, size: 18),
                label: Text(p.stock <= 0 ? 'Sin existencia' : maximo > 0 ? 'Agregar al carrito' : 'Máximo en el carrito'),
              ),
            ),
          ]),
          if (enCarrito > 0) ...[
            const SizedBox(height: 8),
            Text('$enCarrito en tu carrito', style: theme.textTheme.bodySmall?.copyWith(color: AppColors.accent)),
          ],
        ],
      ],
    );

    return Scaffold(
      appBar: AppTopBar(
        leading: IconButton(
          tooltip: 'Volver',
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const Icon(Icons.arrow_back),
        ),
      ),
      body: ListView(
        padding: EdgeInsets.symmetric(vertical: compacto ? 16 : 28, horizontal: compacto ? 16 : 24),
        children: [
          PageBody(
            maxWidth: 1080,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Card(
                  child: Padding(
                    padding: EdgeInsets.all(compacto ? 16 : 24),
                    child: LayoutBuilder(
                      builder: (context, c) => c.maxWidth >= 760
                          ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Expanded(flex: 5, child: foto),
                              const SizedBox(width: 32),
                              Expanded(flex: 6, child: resumen),
                            ])
                          : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                              foto,
                              const SizedBox(height: 20),
                              resumen,
                            ]),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                if (cargando) const LinearProgressIndicator(),
                if (error != null) InlineBanner.error(error!),
                if (detalle != null)
                  LayoutBuilder(builder: (context, c) {
                    final descripcion = _Descripcion(texto: detalle.descripcion);
                    final specs = _Especificaciones(lista: detalle.especificaciones);
                    return c.maxWidth >= 900
                        ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Expanded(flex: 6, child: descripcion),
                            const SizedBox(width: 16),
                            Expanded(flex: 5, child: specs),
                          ])
                        : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                            descripcion,
                            const SizedBox(height: 16),
                            specs,
                          ]);
                  }),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Descripcion extends StatelessWidget {
  const _Descripcion({required this.texto});

  final String? texto;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final parrafos = (texto ?? '').split('\n\n').where((p) => p.trim().isNotEmpty).toList();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Descripción', style: theme.textTheme.titleMedium),
          const SizedBox(height: 12),
          if (parrafos.isEmpty) textoSecundario(context, 'Este producto aún no tiene descripción.'),
          for (final (i, p) in parrafos.indexed) ...[
            if (i > 0) const SizedBox(height: 12),
            Text(p, style: theme.textTheme.bodyMedium?.copyWith(height: 1.5)),
          ],
        ]),
      ),
    );
  }
}

class _Especificaciones extends StatelessWidget {
  const _Especificaciones({required this.lista});

  final List<Especificacion> lista;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
          child: Text('Especificaciones técnicas', style: theme.textTheme.titleMedium),
        ),
        if (lista.isEmpty)
          Padding(padding: const EdgeInsets.fromLTRB(20, 0, 20, 20), child: textoSecundario(context, 'Sin especificaciones.')),
        for (final (i, e) in lista.indexed)
          Container(
            color: i.isEven ? AppColors.background : null,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(flex: 2, child: textoSecundario(context, e.nombre)),
              const SizedBox(width: 12),
              Expanded(flex: 3, child: Text(e.valor, style: theme.textTheme.bodyMedium)),
            ]),
          ),
        const SizedBox(height: 8),
      ]),
    );
  }
}
