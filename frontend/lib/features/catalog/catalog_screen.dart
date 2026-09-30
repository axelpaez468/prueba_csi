import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/widgets/app_shell.dart';
import '../../data/models/producto.dart';
import '../cart/cart_controller.dart';
import '../cart/cart_screen.dart';
import '../shell/app_top_bar.dart';
import 'catalog_controller.dart';
import 'producto_detalle_screen.dart';
import 'producto_tile.dart';

class CatalogScreen extends StatefulWidget {
  const CatalogScreen({super.key});

  @override
  State<CatalogScreen> createState() => _CatalogScreenState();
}

class _CatalogScreenState extends State<CatalogScreen> {
  String _filtro = '';

  /// null: todas las categorías.
  String? _categoria;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => context.read<CatalogController>().cargar());
  }

  @override
  Widget build(BuildContext context) {
    final catalogo = context.watch<CatalogController>();
    final carrito = context.watch<CartController>();

    final termino = _filtro.trim().toLowerCase();
    final categorias = {for (final p in catalogo.items) ?p.categoria}.toList()..sort();
    final visibles = catalogo.items
        .where((p) => _categoria == null || p.categoria == _categoria)
        .where((p) =>
            termino.isEmpty ||
            p.nombre.toLowerCase().contains(termino) ||
            p.codigo.toLowerCase().contains(termino) ||
            (p.marca?.toLowerCase().contains(termino) ?? false))
        .toList();
    final disponibles = catalogo.items.where((p) => p.disponible).length;
    final compacto = Breakpoints.esCompacto(context);

    return Scaffold(
      appBar: const AppTopBar(),
      body: RefreshIndicator(
        onRefresh: catalogo.cargar,
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: PageBody(
                child: PageHeader(
                  titulo: 'Catálogo de productos',
                  subtitulo: catalogo.items.isEmpty
                      ? 'Precios y existencias en tiempo real'
                      : '${catalogo.items.length} productos · $disponibles con existencias',
                  acciones: [
                    SizedBox(
                      width: 280,
                      child: TextField(
                        onChanged: (v) => setState(() => _filtro = v),
                        decoration: const InputDecoration(
                          hintText: 'Buscar por nombre, código o marca',
                          prefixIcon: Icon(Icons.search),
                          isDense: true,
                        ),
                      ),
                    ),
                    if (compacto)
                      IconButton.outlined(
                        tooltip: 'Actualizar',
                        onPressed: catalogo.cargando ? null : catalogo.cargar,
                        icon: const Icon(Icons.refresh),
                      )
                    else
                      OutlinedButton.icon(
                        onPressed: catalogo.cargando ? null : catalogo.cargar,
                        icon: const Icon(Icons.refresh, size: 18),
                        label: const Text('Actualizar'),
                      ),
                  ],
                ),
              ),
            ),
            if (categorias.length > 1)
              SliverToBoxAdapter(
                child: PageBody(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(compacto ? 16 : 24, 0, compacto ? 16 : 24, 16),
                    child: Wrap(spacing: 8, runSpacing: 8, children: [
                      ChoiceChip(
                        label: const Text('Todas'),
                        selected: _categoria == null,
                        onSelected: (_) => setState(() => _categoria = null),
                      ),
                      for (final c in categorias)
                        ChoiceChip(
                          label: Text(c),
                          selected: _categoria == c,
                          onSelected: (sel) => setState(() => _categoria = sel ? c : null),
                        ),
                    ]),
                  ),
                ),
              ),
            if (catalogo.cargando)
              SliverToBoxAdapter(
                child: PageBody(
                  child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: compacto ? 16 : 24),
                      child: const LinearProgressIndicator()),
                ),
              ),
            ..._contenido(context, catalogo, carrito, visibles),
            const SliverToBoxAdapter(child: SizedBox(height: 32)),
          ],
        ),
      ),
    );
  }

  List<Widget> _contenido(
      BuildContext context, CatalogController catalogo, CartController carrito, List<Producto> visibles) {
    if (catalogo.items.isEmpty && catalogo.cargando) return const [];

    if (catalogo.error != null && catalogo.items.isEmpty) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: EmptyState(
            icono: Icons.cloud_off_outlined,
            titulo: 'No se pudo cargar el catálogo',
            mensaje: catalogo.error,
            accion: FilledButton(onPressed: catalogo.cargar, child: const Text('Reintentar')),
          ),
        ),
      ];
    }

    if (visibles.isEmpty) {
      return const [
        SliverFillRemaining(
          hasScrollBody: false,
          child: EmptyState(
            icono: Icons.search_off,
            titulo: 'Sin resultados',
            mensaje: 'No hay productos que coincidan con la búsqueda.',
          ),
        ),
      ];
    }

    return [
      SliverToBoxAdapter(
        child: PageBody(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: Breakpoints.esCompacto(context) ? 16 : 24),
            child: LayoutBuilder(builder: (context, constraints) {
              // Columnas según el ancho real: 1 en celular, 2 en tablet, hasta 4 en escritorio.
              const anchoMinimoTarjeta = 250.0, separacion = 16.0;
              final columnas =
                  ((constraints.maxWidth + separacion) / (anchoMinimoTarjeta + separacion)).floor().clamp(1, 4);
              // Filas armadas a mano en lugar de GridView: la altura sale del contenido (nombres largos,
              // etiquetas que bajan de línea) y todas las tarjetas de una misma fila quedan iguales.
              return Column(
                children: [
                  for (var inicio = 0; inicio < visibles.length; inicio += columnas) ...[
                    if (inicio > 0) const SizedBox(height: separacion),
                    IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (var c = 0; c < columnas; c++) ...[
                            if (c > 0) const SizedBox(width: separacion),
                            Expanded(
                              child: inicio + c < visibles.length
                                  ? _tarjeta(context, carrito, visibles[inicio + c])
                                  : const SizedBox.shrink(),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ],
              );
            }),
          ),
        ),
      ),
    ];
  }

  Widget _tarjeta(BuildContext context, CartController carrito, Producto p) {
    return ProductoTile(
      key: ValueKey(p.id),
      producto: p,
      enCarrito: carrito.cantidadDe(p.id),
      onVerDetalle: () =>
          Navigator.of(context).push(MaterialPageRoute(builder: (_) => ProductoDetalleScreen(producto: p))),
      onAgregar: (cantidad) {
        carrito.agregar(p, cantidad);
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(
            content: Row(children: [
              const Icon(Icons.check_circle, color: Colors.white, size: 18),
              const SizedBox(width: 10),
              Expanded(child: Text('${p.nombre} agregado al carrito')),
            ]),
            action: SnackBarAction(
              label: 'Ver carrito',
              textColor: const Color(0xFF9FE3D0),
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CartScreen())),
            ),
            duration: const Duration(seconds: 3),
            persist: false, // con acción, por defecto no se cierra solo
          ));
      },
    );
  }
}
