import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/network/api_exception.dart';
import '../../core/security/permisos.dart';
import '../../core/theme/app_theme.dart';
import '../../core/util/formatters.dart';
import '../../core/widgets/app_shell.dart';
import '../../core/widgets/erp_widgets.dart';
import '../../data/models/erp.dart';
import '../../data/repositories/erp_repositories.dart';
import '../auth/session_controller.dart';
import '../inventario/inventario_dialogs.dart';
import '../shell/modulo_page.dart';

/// Órdenes de compra: COMPRAS las crea o anula; BODEGA recibe la mercadería con la factura del proveedor.
class OrdenesScreen extends StatefulWidget {
  const OrdenesScreen({super.key});

  @override
  State<OrdenesScreen> createState() => _OrdenesScreenState();
}

class _OrdenesScreenState extends State<OrdenesScreen> with CargaDatos<OrdenesScreen, List<OrdenResumen>> {
  String? _estado = 'PENDIENTE';

  @override
  Future<List<OrdenResumen>> obtener() => context.read<CompraRepository>().ordenes(estado: _estado);

  Future<void> _nueva() async {
    final creada = await Navigator.of(context).push<OrdenCompra>(MaterialPageRoute(builder: (_) => const NuevaOrdenScreen()));
    if (creada == null || !mounted) return;
    avisar(context, 'Orden OC-${creada.numero} creada. Queda pendiente de recibir en bodega.');
    await recargar();
  }

  Future<void> _abrir(OrdenResumen o) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => OrdenDetalleScreen(numero: o.numero)));
    if (mounted) await recargar();
  }

  @override
  Widget build(BuildContext context) {
    final lista = datos ?? const <OrdenResumen>[];
    final gestiona = context.watch<SessionController>().session?.gestionaCompras ?? false;
    final compacto = Breakpoints.esCompacto(context);

    return ModuloPage(
      titulo: 'Órdenes de compra',
      subtitulo: '${lista.length} órdenes · ${formatearMoneda(lista.fold<double>(0, (s, o) => s + o.total))}',
      alRefrescar: recargar,
      fab: gestiona && compacto
          ? FloatingActionButton(tooltip: 'Nueva orden', onPressed: _nueva, child: const Icon(Icons.add_shopping_cart))
          : null,
      acciones: [
        DropdownButton<String?>(
          value: _estado,
          underline: const SizedBox.shrink(),
          items: const [
            DropdownMenuItem(value: 'PENDIENTE', child: Text('Pendientes')),
            DropdownMenuItem(value: 'RECIBIDA', child: Text('Recibidas')),
            DropdownMenuItem(value: 'ANULADA', child: Text('Anuladas')),
            DropdownMenuItem(value: null, child: Text('Todas')),
          ],
          onChanged: (v) {
            setState(() => _estado = v);
            recargar();
          },
        ),
        if (gestiona && !compacto)
          FilledButton.icon(onPressed: _nueva, icon: const Icon(Icons.add_shopping_cart, size: 18), label: const Text('Nueva orden')),
      ],
      children: [
        TablaResponsiva(
          cargando: cargando,
          error: error,
          alReintentar: recargar,
          filas: lista.length,
          alTocar: (i) => _abrir(lista[i]),
          vacio: const EmptyState(icono: Icons.local_shipping_outlined, titulo: 'No hay órdenes en este estado'),
          columnas: const [
            ColumnaTabla('Orden', flex: 2),
            ColumnaTabla('Fecha', flex: 2),
            ColumnaTabla('Proveedor', flex: 4),
            ColumnaTabla('Estado', flex: 2),
            ColumnaTabla('Total', flex: 2, derecha: true),
          ],
          celdas: (i) {
            final o = lista[i];
            return [
              textoFuerte(context, 'OC-${o.numero}', lineas: 1),
              textoSecundario(context, formatearFecha(o.fecha)),
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                textoFuerte(context, o.proveedorNombre, lineas: 1),
                textoSecundario(context,
                    '${o.productos} ${o.productos == 1 ? 'producto' : 'productos'}${o.facturaProveedor == null ? '' : ' · factura ${o.facturaProveedor}'}'),
              ]),
              Pills.estadoOrden(o.estado),
              textoFuerte(context, formatearMoneda(o.total), lineas: 1),
            ];
          },
          ficha: (i) {
            final o = lista[i];
            return Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  textoFuerte(context, 'OC-${o.numero} · ${o.proveedorNombre}', lineas: 1),
                  textoSecundario(context, '${formatearFecha(o.fecha)} · ${formatearMoneda(o.total)}'),
                ]),
              ),
              const SizedBox(width: 8),
              Pills.estadoOrden(o.estado),
            ]);
          },
        ),
      ],
    );
  }
}

class OrdenDetalleScreen extends StatefulWidget {
  const OrdenDetalleScreen({super.key, required this.numero});

  final int numero;

  @override
  State<OrdenDetalleScreen> createState() => _OrdenDetalleScreenState();
}

class _OrdenDetalleScreenState extends State<OrdenDetalleScreen> with CargaDatos<OrdenDetalleScreen, OrdenCompra> {
  bool _procesando = false;

  CompraRepository get _repo => context.read<CompraRepository>();

  @override
  Future<OrdenCompra> obtener() => _repo.orden(widget.numero);

  Future<void> _ejecutar(Future<OrdenCompra> Function() accion, String mensaje) async {
    setState(() => _procesando = true);
    try {
      final o = await accion();
      if (!mounted) return;
      setState(() => datos = o);
      avisar(context, mensaje);
    } on ApiException catch (e) {
      if (mounted) avisar(context, e.message);
    } finally {
      if (mounted) setState(() => _procesando = false);
    }
  }

  Future<void> _recibir() async {
    final factura = await showDialog<String>(context: context, builder: (_) => const _RecibirDialog());
    if (factura == null) return;
    await _ejecutar(() => _repo.recibir(widget.numero, factura), 'Mercadería recibida: el inventario y la contabilidad se actualizaron.');
  }

  Future<void> _anular() async {
    if (!await confirmar(context, 'Anular orden', 'La orden OC-${widget.numero} quedará anulada y ya no se podrá recibir.',
        'Anular', peligrosa: true)) {
      return;
    }
    await _ejecutar(() => _repo.anular(widget.numero), 'Orden anulada.');
  }

  @override
  Widget build(BuildContext context) {
    final o = datos;
    final session = context.watch<SessionController>().session;
    final theme = Theme.of(context);

    return ModuloPage(
      titulo: 'Orden de compra OC-${widget.numero}',
      maxWidth: 900,
      children: [
        if (o != null && o.pendiente)
          Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.end, children: [
            if (session?.gestionaCompras ?? false)
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(foregroundColor: AppColors.danger),
                onPressed: _procesando ? null : _anular,
                icon: const Icon(Icons.block, size: 18),
                label: const Text('Anular'),
              ),
            if (session?.recibeCompras ?? false)
              FilledButton.icon(
                onPressed: _procesando ? null : _recibir,
                icon: const Icon(Icons.inventory, size: 18),
                label: const Text('Recibir mercadería'),
              ),
          ]),
        if (cargando || _procesando) const LinearProgressIndicator(),
        if (error != null) InlineBanner.error(error!, alReintentar: recargar),
        if (o != null) ...[
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Wrap(spacing: 32, runSpacing: 16, children: [
                _Dato('Estado', Pills.estadoOrden(o.estado)),
                _Dato('Proveedor', Text('${o.proveedorNombre}\nNIT ${o.proveedorNit}', style: theme.textTheme.titleSmall)),
                _Dato('Creada', Text('${formatearFecha(o.fecha)}\npor ${o.creadaPor}', style: theme.textTheme.titleSmall)),
                if (o.fechaRecepcion != null)
                  _Dato('Recibida',
                      Text('${formatearFecha(o.fechaRecepcion!)}\npor ${o.recibidaPor} · factura ${o.facturaProveedor}',
                          style: theme.textTheme.titleSmall)),
                if (o.observaciones != null) _Dato('Observaciones', Text(o.observaciones!)),
              ]),
            ),
          ),
          TablaResponsiva(
            filas: o.lineas.length,
            anchoTabla: 620,
            columnas: const [
              ColumnaTabla('Producto', flex: 5),
              ColumnaTabla('Cantidad', flex: 2, derecha: true),
              ColumnaTabla('Costo (sin IVA)', flex: 2, derecha: true),
              ColumnaTabla('Subtotal', flex: 2, derecha: true),
            ],
            celdas: (i) {
              final l = o.lineas[i];
              return [
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  textoFuerte(context, l.nombre, lineas: 1),
                  textoSecundario(context, l.codigo),
                ]),
                Text('${l.cantidad}'),
                Text(formatearMoneda(l.costoUnitario)),
                textoFuerte(context, formatearMoneda(l.subtotal), lineas: 1),
              ];
            },
            ficha: (i) {
              final l = o.lineas[i];
              return Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    textoFuerte(context, l.nombre, lineas: 1),
                    textoSecundario(context, '${l.cantidad} × ${formatearMoneda(l.costoUnitario)}'),
                  ]),
                ),
                textoFuerte(context, formatearMoneda(l.subtotal), lineas: 1),
              ]);
            },
            pie: Column(children: [
              FilaValor('Subtotal (sin IVA)', formatearMoneda(o.subtotal)),
              FilaValor('IVA 12 % (crédito fiscal)', formatearMoneda(o.iva)),
              FilaValor('Total a pagar (contado, desde Bancos)', formatearMoneda(o.total), destacado: true),
            ]),
          ),
        ],
      ],
    );
  }
}

class _Dato extends StatelessWidget {
  const _Dato(this.etiqueta, this.valor);

  final String etiqueta;
  final Widget valor;

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        textoSecundario(context, etiqueta.toUpperCase()),
        const SizedBox(height: 4),
        valor,
      ]);
}

class _RecibirDialog extends StatefulWidget {
  const _RecibirDialog();

  @override
  State<_RecibirDialog> createState() => _RecibirDialogState();
}

class _RecibirDialogState extends State<_RecibirDialog> {
  final _factura = TextEditingController();
  final _form = GlobalKey<FormState>();

  @override
  void dispose() {
    _factura.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Recibir mercadería'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Form(
            key: _form,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const Text('Verifica que llegó todo lo de la orden. Al confirmar, la mercadería entra al inventario '
                  '(recalculando el costo promedio) y se registra el pago de contado desde Bancos.'),
              const SizedBox(height: 16),
              TextFormField(
                controller: _factura,
                autofocus: true,
                inputFormatters: [LengthLimitingTextInputFormatter(40)],
                decoration: const InputDecoration(labelText: 'Factura del proveedor (serie y número)', hintText: 'A-00458'),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Campo obligatorio' : null,
              ),
            ]),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () {
              if (_form.currentState!.validate()) Navigator.of(context).pop(_factura.text.trim());
            },
            child: const Text('Confirmar recepción'),
          ),
        ],
      );
}

/// Línea en edición de una orden nueva.
class _LineaNueva {
  // El costo sugerido es el promedio actual, redondeado a centavos (la API no acepta más de dos decimales).
  _LineaNueva(this.producto)
      : cantidad = 1,
        costo = double.parse(producto.costoPromedio.toStringAsFixed(2));

  final ProductoInventario producto;
  int cantidad;
  double costo;

  double get subtotal => (cantidad * costo * 100).roundToDouble() / 100;
}

class NuevaOrdenScreen extends StatefulWidget {
  const NuevaOrdenScreen({super.key});

  @override
  State<NuevaOrdenScreen> createState() => _NuevaOrdenScreenState();
}

class _NuevaOrdenScreenState extends State<NuevaOrdenScreen>
    with CargaDatos<NuevaOrdenScreen, (List<Proveedor>, List<ProductoInventario>)> {
  final _observaciones = TextEditingController();
  final List<_LineaNueva> _lineas = [];
  Proveedor? _proveedor;
  bool _guardando = false;
  String? _errorGuardar;

  @override
  Future<(List<Proveedor>, List<ProductoInventario>)> obtener() async {
    final compras = context.read<CompraRepository>();
    final inventario = context.read<InventarioRepository>();
    final proveedores = await compras.proveedores();
    final productos = await inventario.listar();
    return (proveedores, productos.where((p) => p.activo).toList());
  }

  @override
  void dispose() {
    _observaciones.dispose();
    super.dispose();
  }

  double get _subtotal => _lineas.fold(0, (s, l) => s + l.subtotal);
  double get _iva => (_subtotal * 0.12 * 100).roundToDouble() / 100;

  Future<void> _guardar() async {
    if (_proveedor == null || _lineas.isEmpty) {
      setState(() => _errorGuardar = 'Elige el proveedor y agrega al menos un producto.');
      return;
    }
    if (_lineas.any((l) => l.cantidad <= 0 || l.costo <= 0)) {
      setState(() => _errorGuardar = 'Cada línea debe tener cantidad y costo mayores que cero.');
      return;
    }
    setState(() {
      _guardando = true;
      _errorGuardar = null;
    });
    try {
      final orden = await context.read<CompraRepository>().crearOrden({
        'proveedorId': _proveedor!.id,
        'observaciones': _observaciones.text.trim(),
        'lineas': [
          for (final l in _lineas) {'productoId': l.producto.id, 'cantidad': l.cantidad, 'costoUnitario': l.costo},
        ],
      });
      if (mounted) Navigator.of(context).pop(orden);
    } on ApiException catch (e) {
      setState(() => _errorGuardar = e.message);
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final proveedores = datos?.$1 ?? const <Proveedor>[];
    final productos = (datos?.$2 ?? const <ProductoInventario>[])
        .where((p) => !_lineas.any((l) => l.producto.id == p.id))
        .toList();

    return ModuloPage(
      titulo: 'Nueva orden de compra',
      subtitulo: 'Costos sin IVA; el sistema agrega el 12 %.',
      maxWidth: 960,
      children: [
        if (cargando) const LinearProgressIndicator(),
        if (error != null) InlineBanner.error(error!, alReintentar: recargar),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              DropdownButtonFormField<Proveedor>(
                initialValue: _proveedor,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Proveedor'),
                items: [
                  for (final p in proveedores)
                    DropdownMenuItem(value: p, child: Text('${p.nombre} · NIT ${p.nitFormateado}', overflow: TextOverflow.ellipsis)),
                ],
                onChanged: _guardando ? null : (p) => setState(() => _proveedor = p),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _observaciones,
                enabled: !_guardando,
                maxLength: 300,
                decoration: const InputDecoration(labelText: 'Observaciones (opcional)'),
              ),
            ]),
          ),
        ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Wrap(alignment: WrapAlignment.spaceBetween, crossAxisAlignment: WrapCrossAlignment.center, children: [
                Text('Productos', style: Theme.of(context).textTheme.titleMedium),
                PopupMenuButton<ProductoInventario>(
                  enabled: !_guardando && productos.isNotEmpty,
                  tooltip: 'Agregar producto',
                  onSelected: (p) => setState(() => _lineas.add(_LineaNueva(p))),
                  itemBuilder: (_) => [
                    for (final p in productos)
                      PopupMenuItem(value: p, child: Text('${p.codigo} · ${p.nombre} (existencia ${p.stock})')),
                  ],
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.add, size: 18, color: AppColors.primary),
                      SizedBox(width: 6),
                      Flexible(
                        child: Text('Agregar producto',
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w600)),
                      ),
                    ]),
                  ),
                ),
              ]),
              const SizedBox(height: 8),
              if (_lineas.isEmpty)
                const EmptyState(icono: Icons.playlist_add, titulo: 'Agrega los productos a comprar'),
              for (final (i, l) in _lineas.indexed) ...[
                if (i > 0) const Divider(),
                _EditorLinea(
                  key: ObjectKey(l),
                  linea: l,
                  habilitado: !_guardando,
                  alCambiar: () => setState(() {}),
                  alQuitar: () => setState(() => _lineas.removeAt(i)),
                ),
              ],
              if (_lineas.isNotEmpty) ...[
                const Divider(thickness: 1.5),
                FilaValor('Subtotal (sin IVA)', formatearMoneda(_subtotal)),
                FilaValor('IVA 12 %', formatearMoneda(_iva)),
                FilaValor('Total', formatearMoneda(_subtotal + _iva), destacado: true),
              ],
            ]),
          ),
        ),
        if (_errorGuardar != null) InlineBanner.error(_errorGuardar!),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton.icon(
            onPressed: _guardando ? null : _guardar,
            icon: const Icon(Icons.save_outlined, size: 18),
            label: Text(_guardando ? 'Guardando...' : 'Crear orden'),
          ),
        ),
      ],
    );
  }
}

class _EditorLinea extends StatefulWidget {
  const _EditorLinea({super.key, required this.linea, required this.habilitado, required this.alCambiar, required this.alQuitar});

  final _LineaNueva linea;
  final bool habilitado;
  final VoidCallback alCambiar;
  final VoidCallback alQuitar;

  @override
  State<_EditorLinea> createState() => _EditorLineaState();
}

class _EditorLineaState extends State<_EditorLinea> {
  late final _cantidad = TextEditingController(text: '${widget.linea.cantidad}');
  late final _costo =
      TextEditingController(text: widget.linea.costo > 0 ? widget.linea.costo.toStringAsFixed(2) : '');

  @override
  void dispose() {
    _cantidad.dispose();
    _costo.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = widget.linea;
    final nombre = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      textoFuerte(context, l.producto.nombre, lineas: 1),
      textoSecundario(context, '${l.producto.codigo} · costo promedio ${formatearMoneda(l.producto.costoPromedio)}'),
    ]);
    final cantidad = TextField(
      controller: _cantidad,
      enabled: widget.habilitado,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
      decoration: const InputDecoration(labelText: 'Cantidad', isDense: true),
      onChanged: (v) {
        l.cantidad = int.tryParse(v) ?? 0;
        widget.alCambiar();
      },
    );
    final costo = TextField(
      controller: _costo,
      enabled: widget.habilitado,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d{0,9}(\.\d{0,2})?'))],
      decoration: const InputDecoration(labelText: 'Costo sin IVA', prefixText: 'Q ', isDense: true),
      onChanged: (v) {
        l.costo = leerMonto(v) ?? 0;
        widget.alCambiar();
      },
    );
    final quitar = IconButton(
      tooltip: 'Quitar',
      onPressed: widget.habilitado ? widget.alQuitar : null,
      icon: const Icon(Icons.delete_outline, color: AppColors.textSecondary),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: LayoutBuilder(builder: (context, c) {
        if (c.maxWidth >= 640) {
          return Row(children: [
            Expanded(flex: 4, child: nombre),
            const SizedBox(width: 12),
            SizedBox(width: 110, child: cantidad),
            const SizedBox(width: 12),
            SizedBox(width: 150, child: costo),
            const SizedBox(width: 12),
            SizedBox(width: 110, child: Text(formatearMoneda(l.subtotal), textAlign: TextAlign.end)),
            quitar,
          ]);
        }
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [Expanded(child: nombre), quitar]),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: cantidad),
            const SizedBox(width: 12),
            Expanded(child: costo),
          ]),
          const SizedBox(height: 6),
          Align(alignment: Alignment.centerRight, child: textoFuerte(context, formatearMoneda(l.subtotal), lineas: 1)),
        ]);
      }),
    );
  }
}
