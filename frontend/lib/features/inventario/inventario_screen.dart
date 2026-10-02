import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/security/permisos.dart';
import '../../core/theme/app_theme.dart';
import '../../core/util/formatters.dart';
import '../../core/widgets/app_shell.dart';
import '../../core/widgets/erp_widgets.dart';
import '../../data/models/erp.dart';
import '../../data/repositories/erp_repositories.dart';
import '../auth/session_controller.dart';
import '../shell/modulo_page.dart';
import 'inventario_dialogs.dart';

/// Existencias valorizadas al costo promedio. BODEGA y ADMIN crean productos y registran ajustes.
class InventarioScreen extends StatefulWidget {
  const InventarioScreen({super.key});

  @override
  State<InventarioScreen> createState() => _InventarioScreenState();
}

class _InventarioScreenState extends State<InventarioScreen> with CargaDatos<InventarioScreen, List<ProductoInventario>> {
  final _buscar = TextEditingController();
  bool _soloBajoMinimo = false;

  @override
  Future<List<ProductoInventario>> obtener() =>
      context.read<InventarioRepository>().listar(buscar: _buscar.text, bajoMinimo: _soloBajoMinimo);

  @override
  void dispose() {
    _buscar.dispose();
    super.dispose();
  }

  Future<void> _producto([ProductoInventario? p]) async {
    final guardado = await showDialog<ProductoInventario>(context: context, builder: (_) => ProductoFormDialog(producto: p));
    if (guardado == null || !mounted) return;
    avisar(context, p == null ? 'Producto ${guardado.codigo} creado.' : 'Cambios guardados.');
    await recargar();
  }

  Future<void> _ajustar(ProductoInventario p) async {
    final mov = await showDialog<MovimientoInventario>(context: context, builder: (_) => AjusteDialog(producto: p));
    if (mov == null || !mounted) return;
    avisar(context, 'Ajuste registrado. Nueva existencia: ${mov.saldo}.');
    await recargar();
  }

  void _kardex(ProductoInventario p) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => KardexScreen(productoId: p.id)));

  @override
  Widget build(BuildContext context) {
    final lista = datos ?? const <ProductoInventario>[];
    final gestiona = context.watch<SessionController>().session?.gestionaInventario ?? false;
    final valor = lista.fold<double>(0, (s, p) => s + p.valorInventario);
    final alertas = lista.where((p) => p.bajoMinimo).length;
    final compacto = Breakpoints.esCompacto(context);

    Widget menu(ProductoInventario p) => PopupMenuButton<String>(
          tooltip: 'Acciones',
          icon: const Icon(Icons.more_vert),
          onSelected: (a) => switch (a) {
            'editar' => _producto(p),
            'ajustar' => _ajustar(p),
            _ => _kardex(p),
          },
          itemBuilder: (_) => [
            const PopupMenuItem(value: 'kardex', child: Text('Ver kardex')),
            if (gestiona) const PopupMenuItem(value: 'ajustar', child: Text('Ajustar existencia')),
            if (gestiona) const PopupMenuItem(value: 'editar', child: Text('Editar producto')),
          ],
        );

    Widget stock(ProductoInventario p) => !p.activo
        ? const StatusPill(texto: 'Inactivo', color: AppColors.textSecondary, fondo: AppColors.background)
        : p.bajoMinimo
            ? StatusPill(
                texto: '${p.stock} · reabastecer',
                color: p.stock == 0 ? AppColors.danger : AppColors.warning,
                fondo: p.stock == 0 ? AppColors.dangerBg : AppColors.warningBg)
            : StatusPill(texto: '${p.stock}', color: AppColors.success, fondo: AppColors.successBg);

    return ModuloPage(
      titulo: 'Inventario',
      subtitulo: '${lista.length} productos · valor ${formatearMoneda(valor)} · $alertas por reabastecer',
      alRefrescar: recargar,
      fab: gestiona && compacto
          ? FloatingActionButton(tooltip: 'Nuevo producto', onPressed: _producto, child: const Icon(Icons.add))
          : null,
      acciones: [
        SizedBox(
          width: 260,
          child: TextField(
            controller: _buscar,
            onSubmitted: (_) => recargar(),
            decoration: const InputDecoration(hintText: 'Buscar por código o nombre', prefixIcon: Icon(Icons.search), isDense: true),
          ),
        ),
        FilterChip(
          label: const Text('Por reabastecer'),
          selected: _soloBajoMinimo,
          onSelected: (v) {
            setState(() => _soloBajoMinimo = v);
            recargar();
          },
        ),
        if (gestiona && !compacto)
          FilledButton.icon(onPressed: _producto, icon: const Icon(Icons.add, size: 18), label: const Text('Nuevo producto')),
      ],
      children: [
        TablaResponsiva(
          cargando: cargando,
          error: error,
          alReintentar: recargar,
          filas: lista.length,
          anchoTabla: 900,
          alTocar: (i) => _kardex(lista[i]),
          columnas: const [
            ColumnaTabla('Producto', flex: 5),
            ColumnaTabla('Precio', flex: 2, derecha: true),
            ColumnaTabla('Costo prom.', flex: 2, derecha: true),
            ColumnaTabla('Margen', flex: 2, derecha: true),
            ColumnaTabla('Existencia', flex: 3, derecha: true),
            ColumnaTabla('Valor', flex: 2, derecha: true),
            ColumnaTabla('', flex: 1, derecha: true),
          ],
          celdas: (i) {
            final p = lista[i];
            return [
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                textoFuerte(context, p.nombre, lineas: 1),
                textoSecundario(context, '${p.codigo} · mínimo ${p.stockMinimo}'),
              ]),
              Text(formatearMoneda(p.precio)),
              Text(formatearMoneda(p.costoPromedio)),
              textoSecundario(context, p.margen == null ? '—' : '${p.margen!.toStringAsFixed(1)} %'),
              stock(p),
              textoFuerte(context, formatearMoneda(p.valorInventario), lineas: 1),
              menu(p),
            ];
          },
          ficha: (i) {
            final p = lista[i];
            return Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  textoFuerte(context, p.nombre, lineas: 1),
                  textoSecundario(context,
                      '${p.codigo} · ${formatearMoneda(p.precio)} · costo ${formatearMoneda(p.costoPromedio)}'),
                  const SizedBox(height: 6),
                  stock(p),
                ]),
              ),
              menu(p),
            ]);
          },
          pie: FilaValor('Valor total del inventario', formatearMoneda(valor), destacado: true),
        ),
      ],
    );
  }
}

/// Kardex del producto: cada entrada y salida con su saldo y costo promedio.
class KardexScreen extends StatefulWidget {
  const KardexScreen({super.key, required this.productoId});

  final int productoId;

  @override
  State<KardexScreen> createState() => _KardexScreenState();
}

class _KardexScreenState extends State<KardexScreen> with CargaDatos<KardexScreen, Kardex> {
  @override
  Future<Kardex> obtener() => context.read<InventarioRepository>().kardex(widget.productoId);

  @override
  Widget build(BuildContext context) {
    final k = datos;
    final movimientos = k?.movimientos.reversed.toList() ?? const <MovimientoInventario>[];

    return ModuloPage(
      titulo: k == null ? 'Kardex' : 'Kardex · ${k.producto.nombre}',
      subtitulo: k == null
          ? null
          : '${k.producto.codigo} · existencia ${k.producto.stock} · costo promedio ${formatearMoneda(k.producto.costoPromedio)}',
      alRefrescar: recargar,
      children: [
        TablaResponsiva(
          cargando: cargando,
          error: error,
          alReintentar: recargar,
          filas: movimientos.length,
          anchoTabla: 860,
          vacio: const EmptyState(icono: Icons.swap_vert, titulo: 'Sin movimientos todavía'),
          columnas: const [
            ColumnaTabla('Fecha', flex: 2),
            ColumnaTabla('Movimiento', flex: 4),
            ColumnaTabla('Entrada', flex: 1, derecha: true),
            ColumnaTabla('Salida', flex: 1, derecha: true),
            ColumnaTabla('Costo unit.', flex: 2, derecha: true),
            ColumnaTabla('Saldo', flex: 1, derecha: true),
            ColumnaTabla('Costo prom.', flex: 2, derecha: true),
          ],
          celdas: (i) {
            final m = movimientos[i];
            return [
              textoSecundario(context, formatearFecha(m.fecha)),
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                textoFuerte(context, m.tipoLegible, lineas: 1),
                textoSecundario(context, [m.referencia, if (m.usuario != null) m.usuario!].join(' · '), lineas: 2),
              ]),
              Text(m.esEntrada ? '${m.cantidad}' : '', style: const TextStyle(color: AppColors.success)),
              Text(m.esEntrada ? '' : '${-m.cantidad}', style: const TextStyle(color: AppColors.danger)),
              Text(formatearMoneda(m.costoUnitario)),
              textoFuerte(context, '${m.saldo}', lineas: 1),
              Text(formatearMoneda(m.costoPromedio)),
            ];
          },
          ficha: (i) {
            final m = movimientos[i];
            return Row(children: [
              Icon(m.esEntrada ? Icons.south_west : Icons.north_east,
                  color: m.esEntrada ? AppColors.success : AppColors.danger, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  textoFuerte(context, '${m.tipoLegible} · ${m.cantidad > 0 ? '+' : ''}${m.cantidad}', lineas: 1),
                  textoSecundario(context, '${formatearFecha(m.fecha)} · ${m.referencia}', lineas: 2),
                ]),
              ),
              const SizedBox(width: 8),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                textoFuerte(context, 'Saldo ${m.saldo}', lineas: 1),
                textoSecundario(context, formatearMoneda(m.costoPromedio)),
              ]),
            ]);
          },
        ),
      ],
    );
  }
}
