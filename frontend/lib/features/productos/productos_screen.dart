import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/network/api_exception.dart';
import '../../core/theme/app_theme.dart';
import '../../core/util/formatters.dart';
import '../../core/widgets/app_shell.dart';
import '../../core/widgets/erp_widgets.dart';
import '../../data/models/erp.dart';
import '../../data/repositories/erp_repositories.dart';
import '../catalog/producto_detalle_screen.dart';
import '../catalog/producto_imagen.dart';
import '../inventario/inventario_dialogs.dart';
import '../shell/modulo_page.dart';

enum _Filtro { todos, activos, inactivos }

/// CRUD de productos (BODEGA y ADMIN): alta, edición de la ficha, fotos, activar/desactivar y eliminar.
/// La existencia no se edita aquí: cambia con compras, ventas y ajustes (módulo Inventario).
class ProductosScreen extends StatefulWidget {
  const ProductosScreen({super.key});

  @override
  State<ProductosScreen> createState() => _ProductosScreenState();
}

class _ProductosScreenState extends State<ProductosScreen> with CargaDatos<ProductosScreen, List<ProductoInventario>> {
  final _buscar = TextEditingController();
  _Filtro _filtro = _Filtro.todos;

  InventarioRepository get _repo => context.read<InventarioRepository>();

  @override
  Future<List<ProductoInventario>> obtener() => _repo.listar(buscar: _buscar.text);

  @override
  void dispose() {
    _buscar.dispose();
    super.dispose();
  }

  Future<void> _formulario([ProductoInventario? p]) async {
    final guardado = await showDialog<ProductoInventario>(context: context, builder: (_) => ProductoFormDialog(producto: p));
    if (guardado == null || !mounted) return;
    avisar(context, p == null ? 'Producto ${guardado.codigo} creado. Agrégale fotos desde "Fotos".' : 'Cambios guardados.');
    await recargar();
  }

  Future<void> _fotos(ProductoInventario p) async {
    await showDialog<void>(context: context, builder: (_) => GaleriaDialog(producto: p));
    if (mounted) await recargar();
  }

  Future<void> _cambiarEstado(ProductoInventario p) async {
    if (p.activo &&
        !await confirmar(context, 'Desactivar producto',
            '${p.nombre} dejará de aparecer en el catálogo y no se podrá vender ni comprar. Su historial se conserva.', 'Desactivar')) {
      return;
    }
    await _ejecutar(() async {
      await _repo.guardar(p.id, _datos(p, activo: !p.activo));
      if (mounted) avisar(context, p.activo ? 'Producto desactivado.' : 'Producto activado.');
    });
  }

  Future<void> _eliminar(ProductoInventario p) async {
    if (!await confirmar(context, 'Eliminar producto',
        'Se eliminará ${p.nombre} con sus fotos. Solo es posible si nunca se vendió, compró ni tuvo movimientos de inventario.',
        'Eliminar',
        peligrosa: true)) {
      return;
    }
    await _ejecutar(() async {
      await _repo.eliminar(p.id);
      if (mounted) avisar(context, 'Producto eliminado.');
    });
  }

  Future<void> _ejecutar(Future<void> Function() accion) async {
    try {
      await accion();
      await recargar();
    } on ApiException catch (e) {
      if (mounted) avisar(context, e.message); // p. ej. "tiene ventas... desactívalo"
    }
  }

  void _ficha(ProductoInventario p) {
    if (!p.activo) {
      avisar(context, 'La ficha pública solo se muestra para productos activos.');
      return;
    }
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => ProductoDetalleScreen(producto: p.comoProducto)));
  }

  static Map<String, dynamic> _datos(ProductoInventario p, {required bool activo}) => {
        'nombre': p.nombre,
        'precio': p.precio,
        'stockMinimo': p.stockMinimo,
        'activo': activo,
        'marca': p.marca,
        'categoria': p.categoria,
        'descripcion': p.descripcion,
        'garantiaMeses': p.garantiaMeses,
        'especificaciones': [for (final e in p.especificaciones) e.toJson()],
      };

  @override
  Widget build(BuildContext context) {
    final todos = datos ?? const <ProductoInventario>[];
    final visibles = todos
        .where((p) => switch (_filtro) {
              _Filtro.todos => true,
              _Filtro.activos => p.activo,
              _Filtro.inactivos => !p.activo,
            })
        .toList();
    final compacto = Breakpoints.esCompacto(context);

    return ModuloPage(
      titulo: 'Productos',
      subtitulo: '${todos.length} productos · ${todos.where((p) => p.activo).length} activos · hasta 5 fotos por producto',
      alRefrescar: recargar,
      fab: compacto ? FloatingActionButton(tooltip: 'Nuevo producto', onPressed: _formulario, child: const Icon(Icons.add)) : null,
      acciones: [
        SizedBox(
          width: 280,
          child: TextField(
            controller: _buscar,
            onSubmitted: (_) => recargar(),
            decoration: const InputDecoration(
                hintText: 'Buscar por código, nombre, marca o categoría', prefixIcon: Icon(Icons.search), isDense: true),
          ),
        ),
        if (!compacto)
          FilledButton.icon(onPressed: _formulario, icon: const Icon(Icons.add, size: 18), label: const Text('Nuevo producto')),
      ],
      children: [
        SegmentedButton<_Filtro>(
          segments: const [
            ButtonSegment(value: _Filtro.todos, label: Text('Todos')),
            ButtonSegment(value: _Filtro.activos, label: Text('Activos')),
            ButtonSegment(value: _Filtro.inactivos, label: Text('Inactivos')),
          ],
          selected: {_filtro},
          showSelectedIcon: false,
          onSelectionChanged: (s) => setState(() => _filtro = s.first),
        ),
        if (cargando) const LinearProgressIndicator(),
        if (error != null) InlineBanner.error(error!, alReintentar: recargar),
        if (!cargando && error == null && visibles.isEmpty)
          const Card(child: EmptyState(icono: Icons.inventory_2_outlined, titulo: 'No hay productos que mostrar')),
        RejillaAdaptable(
          anchoMinimo: 260,
          children: [
            for (final p in visibles)
              _TarjetaProducto(
                producto: p,
                alElegir: (accion) => switch (accion) {
                  'ficha' => _ficha(p),
                  'editar' => _formulario(p),
                  'fotos' => _fotos(p),
                  'estado' => _cambiarEstado(p),
                  _ => _eliminar(p),
                },
              ),
          ],
        ),
      ],
    );
  }
}

class _TarjetaProducto extends StatelessWidget {
  const _TarjetaProducto({required this.producto, required this.alElegir});

  final ProductoInventario producto;
  final ValueChanged<String> alElegir;

  @override
  Widget build(BuildContext context) {
    final p = producto;
    final theme = Theme.of(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SizedBox(
          height: 150,
          child: Stack(fit: StackFit.expand, children: [
            InkWell(
              onTap: () => alElegir('fotos'),
              child: Opacity(opacity: p.activo ? 1 : 0.5, child: ProductoImagen(producto: p.comoProducto)),
            ),
            Positioned(
              left: 10,
              top: 10,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(99)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.photo_library_outlined, size: 14, color: Colors.white),
                  const SizedBox(width: 4),
                  Text('${p.imagenes.length}/5', style: const TextStyle(color: Colors.white, fontSize: 12)),
                ]),
              ),
            ),
            if (!p.activo)
              const Positioned(
                right: 10,
                top: 10,
                child: StatusPill(texto: 'Inactivo', color: AppColors.danger, fondo: AppColors.dangerBg),
              ),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 4, 12),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                textoFuerte(context, p.nombre, lineas: 2),
                textoSecundario(context, [p.codigo, ?p.marca, ?p.categoria].join(' · '), lineas: 1),
                const SizedBox(height: 8),
                Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  Text(formatearMoneda(p.precio), style: theme.textTheme.titleMedium?.copyWith(color: AppColors.primary)),
                  StatusPill(
                    texto: '${p.stock} en existencia',
                    color: p.bajoMinimo ? AppColors.warning : AppColors.textSecondary,
                    fondo: p.bajoMinimo ? AppColors.warningBg : AppColors.background,
                  ),
                ]),
              ]),
            ),
            PopupMenuButton<String>(
              tooltip: 'Acciones',
              icon: const Icon(Icons.more_vert),
              onSelected: alElegir,
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'ficha', child: Text('Ver ficha')),
                const PopupMenuItem(value: 'editar', child: Text('Editar ficha')),
                const PopupMenuItem(value: 'fotos', child: Text('Fotos')),
                PopupMenuItem(value: 'estado', child: Text(p.activo ? 'Desactivar' : 'Activar')),
                const PopupMenuDivider(),
                const PopupMenuItem(value: 'eliminar', child: Text('Eliminar', style: TextStyle(color: AppColors.danger))),
              ],
            ),
          ]),
        ),
      ]),
    );
  }
}

/// Gestor de fotos del producto: subir (JPG, PNG o WebP de hasta 2 MB), elegir la principal y eliminar.
class GaleriaDialog extends StatefulWidget {
  const GaleriaDialog({super.key, required this.producto});

  final ProductoInventario producto;

  @override
  State<GaleriaDialog> createState() => _GaleriaDialogState();
}

class _GaleriaDialogState extends State<GaleriaDialog> {
  static const _maximo = 5;
  static const _tamanoMaximo = 2 * 1024 * 1024;

  late List<int> _imagenes = widget.producto.imagenes;
  bool _trabajando = false;
  String? _error;

  InventarioRepository get _repo => context.read<InventarioRepository>();

  Future<void> _ejecutar(Future<List<int>> Function() accion) async {
    setState(() {
      _trabajando = true;
      _error = null;
    });
    try {
      final ids = await accion();
      if (mounted) setState(() => _imagenes = ids);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _trabajando = false);
    }
  }

  Future<void> _subir() async {
    final archivo = await FilePicker.pickFile(type: FileType.custom, allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp']);
    if (archivo == null) return;
    final bytes = await archivo.readAsBytes();
    if (bytes.length > _tamanoMaximo) {
      setState(() => _error = 'La imagen pesa ${(bytes.length / 1024 / 1024).toStringAsFixed(1)} MB; el máximo es 2 MB.');
      return;
    }
    await _ejecutar(() => _repo.subirImagen(widget.producto.id, bytes, archivo.name));
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.producto.comoProducto;
    return AlertDialog(
      title: Text('Fotos · ${widget.producto.nombre}', maxLines: 2, overflow: TextOverflow.ellipsis),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      content: SizedBox(
        width: 620,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            textoSecundario(context,
                'La primera es la principal (la del catálogo). Hasta $_maximo fotos JPG, PNG o WebP de máximo 2 MB.'),
            const SizedBox(height: 12),
            if (_trabajando) const LinearProgressIndicator(),
            if (_error != null) ...[const SizedBox(height: 8), InlineBanner.error(_error!)],
            const SizedBox(height: 8),
            if (_imagenes.isEmpty)
              const EmptyState(icono: Icons.add_photo_alternate_outlined, titulo: 'Este producto aún no tiene fotos'),
            Wrap(spacing: 12, runSpacing: 12, children: [
              for (final (i, id) in _imagenes.indexed)
                SizedBox(
                  width: 180,
                  child: Card(
                    clipBehavior: Clip.antiAlias,
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      SizedBox(height: 120, child: ProductoImagen(producto: p, imagenId: id, tamanoIcono: 32)),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Row(children: [
                          Expanded(
                            child: i == 0
                                ? const Padding(
                                    padding: EdgeInsets.only(left: 6),
                                    child: StatusPill(texto: 'Principal', color: AppColors.success, fondo: AppColors.successBg),
                                  )
                                : TextButton(
                                    onPressed: _trabajando ? null : () => _ejecutar(() => _repo.imagenPrincipal(widget.producto.id, id)),
                                    child: const Text('Hacer principal'),
                                  ),
                          ),
                          IconButton(
                            tooltip: 'Eliminar foto',
                            onPressed: _trabajando ? null : () => _ejecutar(() => _repo.eliminarImagen(widget.producto.id, id)),
                            icon: const Icon(Icons.delete_outline, color: AppColors.danger, size: 20),
                          ),
                        ]),
                      ),
                    ]),
                  ),
                ),
            ]),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cerrar')),
        FilledButton.icon(
          onPressed: _trabajando || _imagenes.length >= _maximo ? null : _subir,
          icon: const Icon(Icons.upload, size: 18),
          label: Text(_imagenes.length >= _maximo ? 'Máximo $_maximo fotos' : 'Subir foto'),
        ),
      ],
    );
  }
}
