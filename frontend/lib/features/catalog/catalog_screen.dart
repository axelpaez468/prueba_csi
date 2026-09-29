import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../auth/session_controller.dart';
import '../cart/cart_controller.dart';
import '../cart/cart_screen.dart';
import 'catalog_controller.dart';
import 'producto_tile.dart';

class CatalogScreen extends StatefulWidget {
  const CatalogScreen({super.key});

  @override
  State<CatalogScreen> createState() => _CatalogScreenState();
}

class _CatalogScreenState extends State<CatalogScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => context.read<CatalogController>().cargar());
  }

  @override
  Widget build(BuildContext context) {
    final catalogo = context.watch<CatalogController>();
    final carrito = context.watch<CartController>();
    final session = context.watch<SessionController>().session;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Catálogo'),
        actions: [
          if (session != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Center(child: Text('${session.username} (${session.rol})')),
            ),
          IconButton(
            tooltip: 'Actualizar',
            onPressed: catalogo.cargando ? null : catalogo.cargar,
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: 'Carrito',
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CartScreen())),
            icon: Badge(
              isLabelVisible: carrito.totalUnidades > 0,
              label: Text('${carrito.totalUnidades}'),
              child: const Icon(Icons.shopping_cart_outlined),
            ),
          ),
          IconButton(
            tooltip: 'Cerrar sesión',
            onPressed: () => context.read<SessionController>().logout(),
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: _cuerpo(context, catalogo, carrito),
        ),
      ),
    );
  }

  Widget _cuerpo(BuildContext context, CatalogController catalogo, CartController carrito) {
    if (catalogo.cargando && catalogo.items.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (catalogo.error != null && catalogo.items.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(catalogo.error!, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: catalogo.cargar, child: const Text('Reintentar')),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: catalogo.cargar,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (catalogo.cargando) const LinearProgressIndicator(),
          for (final p in catalogo.items)
            ProductoTile(
              key: ValueKey(p.id),
              producto: p,
              enCarrito: carrito.cantidadDe(p.id),
              onAgregar: (cantidad) {
                carrito.agregar(p, cantidad);
                ScaffoldMessenger.of(context)
                  ..hideCurrentSnackBar()
                  ..showSnackBar(SnackBar(
                    content: Text('${p.nombre} agregado al carrito'),
                    duration: const Duration(seconds: 2),
                  ));
              },
            ),
        ],
      ),
    );
  }
}
