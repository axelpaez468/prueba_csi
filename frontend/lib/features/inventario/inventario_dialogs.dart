import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/network/api_exception.dart';
import '../../core/util/formatters.dart';
import '../../core/widgets/app_shell.dart';
import '../../data/models/erp.dart';
import '../../data/repositories/erp_repositories.dart';

final _formatoMonto = FilteringTextInputFormatter.allow(RegExp(r'^\d{0,9}(\.\d{0,2})?'));

double? leerMonto(String texto) => double.tryParse(texto.trim().replaceAll(',', ''));

/// Alta o edición de producto. La existencia no se edita aquí: cambia solo con compras, ventas y ajustes.
class ProductoFormDialog extends StatefulWidget {
  const ProductoFormDialog({super.key, this.producto});

  final ProductoInventario? producto;

  @override
  State<ProductoFormDialog> createState() => _ProductoFormDialogState();
}

class _ProductoFormDialogState extends State<ProductoFormDialog> {
  final _form = GlobalKey<FormState>();
  late final _codigo = TextEditingController(text: widget.producto?.codigo);
  late final _nombre = TextEditingController(text: widget.producto?.nombre);
  late final _precio = TextEditingController(text: widget.producto?.precio.toStringAsFixed(2));
  late final _minimo = TextEditingController(text: '${widget.producto?.stockMinimo ?? 0}');
  late bool _activo = widget.producto?.activo ?? true;
  bool _guardando = false;
  String? _error;

  bool get _esNuevo => widget.producto == null;

  @override
  void dispose() {
    for (final c in [_codigo, _nombre, _precio, _minimo]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _guardar() async {
    if (_guardando || !_form.currentState!.validate()) return;
    setState(() {
      _guardando = true;
      _error = null;
    });
    try {
      final guardado = await context.read<InventarioRepository>().guardar(widget.producto?.id, {
        'codigo': _codigo.text.trim().toUpperCase(),
        'nombre': _nombre.text.trim(),
        'precio': leerMonto(_precio.text),
        'stockMinimo': int.parse(_minimo.text),
        'activo': _activo,
      });
      if (mounted) Navigator.of(context).pop(guardado);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_esNuevo ? 'Nuevo producto' : 'Editar producto'),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: SingleChildScrollView(
          child: Form(
            key: _form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: _codigo,
                  enabled: _esNuevo && !_guardando,
                  textCapitalization: TextCapitalization.characters,
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9\-]')), LengthLimitingTextInputFormatter(20)],
                  decoration: InputDecoration(
                    labelText: 'Código',
                    hintText: 'P-006',
                    helperText: _esNuevo ? null : 'El código no cambia: lo usan las facturas y el kardex.',
                  ),
                  validator: (v) => RegExp(r'^[A-Z0-9][A-Z0-9\-]{2,19}$').hasMatch((v ?? '').trim().toUpperCase())
                      ? null
                      : '3 a 20 letras, números o guiones',
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _nombre,
                  enabled: !_guardando,
                  decoration: const InputDecoration(labelText: 'Nombre'),
                  validator: (v) => (v == null || v.trim().length < 2) ? 'Campo obligatorio' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _precio,
                  enabled: !_guardando,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [_formatoMonto],
                  decoration: const InputDecoration(labelText: 'Precio de venta (IVA incluido)', prefixText: 'Q '),
                  validator: (v) => (leerMonto(v ?? '') ?? 0) > 0 ? null : 'Ingresa un precio mayor que cero',
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _minimo,
                  enabled: !_guardando,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
                  decoration: const InputDecoration(
                      labelText: 'Stock mínimo', helperText: 'Al llegar a esta existencia se marca para reabastecer.'),
                  validator: (v) => int.tryParse(v ?? '') == null ? 'Ingresa un número' : null,
                ),
                if (!_esNuevo) ...[
                  const SizedBox(height: 8),
                  Casilla(
                    valor: _activo,
                    alCambiar: _guardando ? null : (v) => setState(() => _activo = v),
                    texto: 'Activo',
                    detalle: 'Un producto inactivo no aparece en el catálogo ni se puede comprar.',
                  ),
                ],
                if (_esNuevo) ...[
                  const SizedBox(height: 12),
                  const InlineBanner.info('Empieza con existencia 0. Ingrésala con una orden de compra o un ajuste de entrada.'),
                ],
                if (_error != null) ...[const SizedBox(height: 12), InlineBanner.error(_error!)],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _guardando ? null : () => Navigator.of(context).pop(), child: const Text('Cancelar')),
        FilledButton(onPressed: _guardando ? null : _guardar, child: Text(_guardando ? 'Guardando...' : 'Guardar')),
      ],
    );
  }
}

/// Ajuste de inventario (conteo físico, daño, merma, sobrante). Queda en el kardex y en contabilidad.
class AjusteDialog extends StatefulWidget {
  const AjusteDialog({super.key, required this.producto});

  final ProductoInventario producto;

  @override
  State<AjusteDialog> createState() => _AjusteDialogState();
}

class _AjusteDialogState extends State<AjusteDialog> {
  final _form = GlobalKey<FormState>();
  final _cantidad = TextEditingController();
  late final _costo = TextEditingController(
      text: widget.producto.costoPromedio > 0 ? widget.producto.costoPromedio.toStringAsFixed(2) : '');
  final _motivo = TextEditingController();
  String _tipo = 'SALIDA';
  bool _guardando = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [_cantidad, _costo, _motivo]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _guardar() async {
    if (_guardando || !_form.currentState!.validate()) return;
    setState(() {
      _guardando = true;
      _error = null;
    });
    try {
      final mov = await context.read<InventarioRepository>().ajustar({
        'productoId': widget.producto.id,
        'tipo': _tipo,
        'cantidad': int.parse(_cantidad.text),
        if (_tipo == 'ENTRADA') 'costoUnitario': leerMonto(_costo.text),
        'motivo': _motivo.text.trim(),
      });
      if (mounted) Navigator.of(context).pop(mov);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.producto;
    return AlertDialog(
      title: const Text('Ajuste de inventario'),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: SingleChildScrollView(
          child: Form(
            key: _form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('${p.codigo} · ${p.nombre}', style: Theme.of(context).textTheme.titleSmall),
                Text('Existencia actual: ${p.stock} · costo promedio ${formatearMoneda(p.costoPromedio)}'),
                const SizedBox(height: 16),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'SALIDA', label: Text('Salida'), icon: Icon(Icons.remove_circle_outline)),
                    ButtonSegment(value: 'ENTRADA', label: Text('Entrada'), icon: Icon(Icons.add_circle_outline)),
                  ],
                  selected: {_tipo},
                  onSelectionChanged: _guardando ? null : (s) => setState(() => _tipo = s.first),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _cantidad,
                  enabled: !_guardando,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
                  decoration: const InputDecoration(labelText: 'Cantidad'),
                  validator: (v) {
                    final n = int.tryParse(v ?? '') ?? 0;
                    if (n <= 0) return 'Ingresa una cantidad mayor que cero';
                    if (_tipo == 'SALIDA' && n > p.stock) return 'Solo hay ${p.stock} en existencia';
                    return null;
                  },
                ),
                if (_tipo == 'ENTRADA') ...[
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _costo,
                    enabled: !_guardando,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [_formatoMonto],
                    decoration: const InputDecoration(labelText: 'Costo unitario (sin IVA)', prefixText: 'Q '),
                    validator: (v) => (leerMonto(v ?? '') ?? 0) > 0 ? null : 'Ingresa el costo',
                  ),
                ],
                const SizedBox(height: 12),
                TextFormField(
                  controller: _motivo,
                  enabled: !_guardando,
                  maxLength: 100,
                  decoration: const InputDecoration(labelText: 'Motivo', hintText: 'Producto dañado, conteo físico...'),
                  validator: (v) => (v == null || v.trim().length < 5) ? 'Describe el motivo (mínimo 5 caracteres)' : null,
                ),
                InlineBanner.info(_tipo == 'SALIDA'
                    ? 'La salida se registra como gasto (faltantes y mermas) al costo promedio.'
                    : 'La entrada se registra como otro ingreso (sobrante) y recalcula el costo promedio.'),
                if (_error != null) ...[const SizedBox(height: 12), InlineBanner.error(_error!)],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _guardando ? null : () => Navigator.of(context).pop(), child: const Text('Cancelar')),
        FilledButton(onPressed: _guardando ? null : _guardar, child: Text(_guardando ? 'Registrando...' : 'Registrar ajuste')),
      ],
    );
  }
}
