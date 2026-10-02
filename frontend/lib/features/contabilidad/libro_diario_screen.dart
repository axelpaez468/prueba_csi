import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/network/api_exception.dart';
import '../../core/theme/app_theme.dart';
import '../../core/util/formatters.dart';
import '../../core/widgets/app_shell.dart';
import '../../core/widgets/erp_widgets.dart';
import '../../data/models/erp.dart';
import '../../data/repositories/erp_repositories.dart';
import '../inventario/inventario_dialogs.dart';
import '../shell/modulo_page.dart';

/// Libro diario: partidas automáticas (ventas, compras, ajustes) y manuales, con sus cargos y abonos.
class LibroDiarioScreen extends StatefulWidget {
  const LibroDiarioScreen({super.key});

  @override
  State<LibroDiarioScreen> createState() => _LibroDiarioScreenState();
}

class _LibroDiarioScreenState extends State<LibroDiarioScreen> with CargaDatos<LibroDiarioScreen, List<Partida>> {
  DateTime _desde = inicioDeMes();
  DateTime _hasta = hoy();
  String? _origen;
  final _paginacion = Paginacion(porPagina: 10);

  @override
  Future<List<Partida>> obtener() => context.read<ContabilidadRepository>().libroDiario(_desde, _hasta, origen: _origen);

  Future<void> _nueva() async {
    final creada = await Navigator.of(context).push<Partida>(MaterialPageRoute(builder: (_) => const NuevaPartidaScreen()));
    if (creada == null || !mounted) return;
    avisar(context, 'Partida #${creada.numero} registrada.');
    await recargar();
  }

  @override
  Widget build(BuildContext context) {
    final lista = datos ?? const <Partida>[];
    final compacto = Breakpoints.esCompacto(context);

    return ModuloPage(
      titulo: 'Libro diario',
      subtitulo: '${lista.length} partidas · ${formatearMoneda(lista.fold<double>(0, (s, p) => s + p.total))}',
      alRefrescar: recargar,
      fab: compacto ? FloatingActionButton(tooltip: 'Nueva partida', onPressed: _nueva, child: const Icon(Icons.post_add)) : null,
      acciones: [
        SelectorRango(
          desde: _desde,
          hasta: _hasta,
          alCambiar: (d, h) {
            setState(() {
              _desde = d;
              _hasta = h;
            });
            recargar();
          },
        ),
        if (!compacto) _filtroOrigen(),
        if (!compacto)
          FilledButton.icon(onPressed: _nueva, icon: const Icon(Icons.post_add, size: 18), label: const Text('Nueva partida')),
      ],
      children: [
        if (compacto) _filtroOrigen(expandido: true),
        if (cargando) const LinearProgressIndicator(),
        if (error != null) InlineBanner.error(error!, alReintentar: recargar),
        if (!cargando && error == null && lista.isEmpty)
          const Card(child: EmptyState(icono: Icons.menu_book_outlined, titulo: 'No hay partidas en este rango')),
        for (final p in _paginacion.recortar(lista)) _TarjetaPartida(partida: p),
        if (Paginacion.necesaria(lista.length))
          Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Paginador(
                                total: lista.length,
                                pagina: _paginacion.pagina,
                                porPagina: _paginacion.porPagina,
                                alCambiarPagina: (p) => setState(() => _paginacion.pagina = p),
                                alCambiarPorPagina: (n) => setState(() {
                                  _paginacion.porPagina = n;
                                  _paginacion.pagina = 0;
                                }),
                              ),
            ),
          ),
      ],
    );
  }

  Widget _filtroOrigen({bool expandido = false}) => DropdownButton<String?>(
          value: _origen,
          isExpanded: expandido,
          underline: const SizedBox.shrink(),
          items: const [
            DropdownMenuItem(value: null, child: Text('Todos los orígenes')),
            DropdownMenuItem(value: 'VENTA', child: Text('Ventas')),
            DropdownMenuItem(value: 'COMPRA', child: Text('Compras')),
            DropdownMenuItem(value: 'AJUSTE', child: Text('Ajustes')),
            DropdownMenuItem(value: 'MANUAL', child: Text('Manuales')),
            DropdownMenuItem(value: 'APERTURA', child: Text('Apertura')),
          ],
          onChanged: (v) {
            setState(() => _origen = v);
            recargar();
          },
        );
}

class _TarjetaPartida extends StatelessWidget {
  const _TarjetaPartida({required this.partida});

  final Partida partida;

  @override
  Widget build(BuildContext context) {
    final p = partida;
    final theme = Theme.of(context);
    final ancho = Breakpoints.esCompacto(context) ? 96.0 : 120.0;
    Widget monto(double v, {bool fuerte = false}) => SizedBox(
          width: ancho,
          child: Align(
            alignment: Alignment.centerRight,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: fuerte ? textoFuerte(context, formatearMoneda(v), lineas: 1) : Text(v > 0 ? formatearMoneda(v) : ''),
            ),
          ),
        );
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Partida #${p.numero} · ${formatearDia(p.fecha)}', style: theme.textTheme.titleSmall),
                const SizedBox(height: 2),
                textoSecundario(context, p.concepto),
              ]),
            ),
            const SizedBox(width: 8),
            Pills.origen(p.origen),
          ]),
          const SizedBox(height: 10),
          const Divider(),
          for (final l in p.lineas)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(children: [
                Expanded(
                  child: Padding(
                    // Los abonos se sangran, como en el libro diario tradicional.
                    padding: EdgeInsets.only(left: l.haber > 0 ? 24 : 0),
                    child: Text('${l.codigo} ${l.cuenta}', maxLines: 2, overflow: TextOverflow.ellipsis),
                  ),
                ),
                monto(l.debe),
                monto(l.haber),
              ]),
            ),
          const Divider(),
          Row(children: [
            Expanded(child: textoSecundario(context, 'Sumas iguales')),
            monto(p.total, fuerte: true),
            monto(p.total, fuerte: true),
          ]),
        ]),
      ),
    );
  }
}

class _LineaEditable {
  CuentaContable? cuenta;
  final debe = TextEditingController();
  final haber = TextEditingController();

  double get montoDebe => leerMonto(debe.text) ?? 0;
  double get montoHaber => leerMonto(haber.text) ?? 0;

  void dispose() {
    debe.dispose();
    haber.dispose();
  }
}

/// Partida manual: gastos, aportes, pagos... Solo se guarda si el debe y el haber suman lo mismo.
class NuevaPartidaScreen extends StatefulWidget {
  const NuevaPartidaScreen({super.key});

  @override
  State<NuevaPartidaScreen> createState() => _NuevaPartidaScreenState();
}

class _NuevaPartidaScreenState extends State<NuevaPartidaScreen> with CargaDatos<NuevaPartidaScreen, List<CuentaContable>> {
  final _concepto = TextEditingController();
  final List<_LineaEditable> _lineas = [_LineaEditable(), _LineaEditable()];
  DateTime _fecha = hoy();
  bool _guardando = false;
  String? _errorGuardar;

  @override
  Future<List<CuentaContable>> obtener() async =>
      (await context.read<ContabilidadRepository>().cuentas()).where((c) => c.activa).toList();

  @override
  void dispose() {
    _concepto.dispose();
    for (final l in _lineas) {
      l.dispose();
    }
    super.dispose();
  }

  double get _debe => _lineas.fold(0, (s, l) => s + l.montoDebe);
  double get _haber => _lineas.fold(0, (s, l) => s + l.montoHaber);
  bool get _cuadra => _debe > 0 && (_debe - _haber).abs() < 0.005;

  Future<void> _guardar() async {
    final validas = _lineas.where((l) => l.cuenta != null && (l.montoDebe > 0 || l.montoHaber > 0)).toList();
    if (_concepto.text.trim().length < 5) {
      setState(() => _errorGuardar = 'Escribe el concepto de la partida (mínimo 5 caracteres).');
      return;
    }
    if (validas.length < 2 || !_cuadra) {
      setState(() => _errorGuardar = 'La partida necesita al menos dos líneas y que el debe sea igual al haber.');
      return;
    }
    setState(() {
      _guardando = true;
      _errorGuardar = null;
    });
    try {
      final partida = await context.read<ContabilidadRepository>().crearPartida({
        'fecha': fechaIso(_fecha),
        'concepto': _concepto.text.trim(),
        'lineas': [
          for (final l in validas) {'cuentaId': l.cuenta!.id, 'debe': l.montoDebe, 'haber': l.montoHaber},
        ],
      });
      if (mounted) Navigator.of(context).pop(partida);
    } on ApiException catch (e) {
      setState(() => _errorGuardar = e.message);
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cuentas = datos ?? const <CuentaContable>[];
    final diferencia = _debe - _haber;
    final formato = [FilteringTextInputFormatter.allow(RegExp(r'^\d{0,9}(\.\d{0,2})?'))];

    return ModuloPage(
      titulo: 'Nueva partida',
      subtitulo: 'Cada línea va al debe o al haber. Las sumas deben ser iguales.',
      maxWidth: 960,
      children: [
        if (cargando) const LinearProgressIndicator(),
        if (error != null) InlineBanner.error(error!, alReintentar: recargar),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Wrap(spacing: 12, runSpacing: 12, crossAxisAlignment: WrapCrossAlignment.center, children: [
                SelectorFecha(fecha: _fecha, etiqueta: 'Fecha', alCambiar: (f) => setState(() => _fecha = f)),
              ]),
              const SizedBox(height: 12),
              TextField(
                controller: _concepto,
                enabled: !_guardando,
                maxLength: 200,
                decoration: const InputDecoration(labelText: 'Concepto', hintText: 'Pago de alquiler del local, octubre'),
              ),
            ]),
          ),
        ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              for (final (i, l) in _lineas.indexed) ...[
                if (i > 0) const SizedBox(height: 12),
                LayoutBuilder(builder: (context, c) {
                  final cuenta = DropdownButtonFormField<CuentaContable>(
                    initialValue: l.cuenta,
                    isExpanded: true,
                    decoration: InputDecoration(labelText: 'Cuenta ${i + 1}', isDense: true),
                    items: [
                      for (final cta in cuentas)
                        DropdownMenuItem(value: cta, child: Text(cta.descripcion, overflow: TextOverflow.ellipsis)),
                    ],
                    onChanged: _guardando ? null : (v) => setState(() => l.cuenta = v),
                  );
                  final debe = TextField(
                    controller: l.debe,
                    enabled: !_guardando,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: formato,
                    decoration: const InputDecoration(labelText: 'Debe', prefixText: 'Q ', isDense: true),
                    onChanged: (v) => setState(() {
                      if (v.isNotEmpty) l.haber.clear();
                    }),
                  );
                  final haber = TextField(
                    controller: l.haber,
                    enabled: !_guardando,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: formato,
                    decoration: const InputDecoration(labelText: 'Haber', prefixText: 'Q ', isDense: true),
                    onChanged: (v) => setState(() {
                      if (v.isNotEmpty) l.debe.clear();
                    }),
                  );
                  final quitar = IconButton(
                    tooltip: 'Quitar línea',
                    onPressed: _guardando || _lineas.length <= 2
                        ? null
                        : () => setState(() => _lineas.removeAt(i).dispose()),
                    icon: const Icon(Icons.close, color: AppColors.textSecondary),
                  );
                  return c.maxWidth >= 680
                      ? Row(children: [
                          Expanded(child: cuenta),
                          const SizedBox(width: 12),
                          SizedBox(width: 140, child: debe),
                          const SizedBox(width: 12),
                          SizedBox(width: 140, child: haber),
                          quitar,
                        ])
                      : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                          Row(children: [Expanded(child: cuenta), quitar]),
                          const SizedBox(height: 8),
                          Row(children: [Expanded(child: debe), const SizedBox(width: 12), Expanded(child: haber)]),
                        ]);
                }),
              ],
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _guardando || _lineas.length >= 50 ? null : () => setState(() => _lineas.add(_LineaEditable())),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Agregar línea'),
                ),
              ),
              const Divider(thickness: 1.5),
              FilaValor('Total debe', formatearMoneda(_debe)),
              FilaValor('Total haber', formatearMoneda(_haber)),
              FilaValor(
                _cuadra ? 'La partida cuadra' : 'Diferencia',
                _cuadra ? '✓' : formatearMoneda(diferencia.abs()),
                destacado: true,
                color: _cuadra ? AppColors.success : AppColors.danger,
              ),
            ]),
          ),
        ),
        if (_errorGuardar != null) InlineBanner.error(_errorGuardar!),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton.icon(
            onPressed: _guardando || !_cuadra ? null : _guardar,
            icon: const Icon(Icons.save_outlined, size: 18),
            label: Text(_guardando ? 'Guardando...' : 'Registrar partida'),
          ),
        ),
      ],
    );
  }
}
