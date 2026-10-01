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
import '../shell/modulo_page.dart';

/// Catálogo de cuentas con su saldo actual. Tocar una cuenta abre su libro mayor.
class CuentasScreen extends StatefulWidget {
  const CuentasScreen({super.key});

  @override
  State<CuentasScreen> createState() => _CuentasScreenState();
}

class _CuentasScreenState extends State<CuentasScreen> with CargaDatos<CuentasScreen, List<CuentaContable>> {
  @override
  Future<List<CuentaContable>> obtener() => context.read<ContabilidadRepository>().cuentas();

  Future<void> _abrir([CuentaContable? c]) async {
    final guardada = await showDialog<CuentaContable>(context: context, builder: (_) => _CuentaDialog(cuenta: c));
    if (guardada == null || !mounted) return;
    avisar(context, c == null ? 'Cuenta ${guardada.codigo} creada.' : 'Cambios guardados.');
    await recargar();
  }

  void _mayor(CuentaContable c) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => LibroMayorScreen(cuenta: c)));

  @override
  Widget build(BuildContext context) {
    final lista = datos ?? const <CuentaContable>[];
    final compacto = Breakpoints.esCompacto(context);

    return ModuloPage(
      titulo: 'Catálogo de cuentas',
      subtitulo: 'El primer dígito del código indica el tipo: 1 activo · 2 pasivo · 3 capital · 4 ingreso · 5 costo · 6 gasto',
      alRefrescar: recargar,
      fab: compacto ? FloatingActionButton(tooltip: 'Nueva cuenta', onPressed: _abrir, child: const Icon(Icons.add)) : null,
      acciones: [
        if (!compacto) FilledButton.icon(onPressed: _abrir, icon: const Icon(Icons.add, size: 18), label: const Text('Nueva cuenta')),
      ],
      children: [
        TablaResponsiva(
          cargando: cargando,
          error: error,
          alReintentar: recargar,
          filas: lista.length,
          alTocar: (i) => _mayor(lista[i]),
          columnas: const [
            ColumnaTabla('Código', flex: 1),
            ColumnaTabla('Cuenta', flex: 5),
            ColumnaTabla('Tipo', flex: 2),
            ColumnaTabla('Saldo', flex: 2, derecha: true),
            ColumnaTabla('', flex: 1, derecha: true),
          ],
          celdas: (i) {
            final c = lista[i];
            return [
              textoFuerte(context, c.codigo, lineas: 1),
              Row(children: [
                Flexible(child: Text(c.nombre, overflow: TextOverflow.ellipsis)),
                if (!c.activa) ...[const SizedBox(width: 8), Pills.activo(false)],
              ]),
              textoSecundario(context, tipoCuentaLegible(c.tipo)),
              textoFuerte(context, formatearMoneda(c.saldo), lineas: 1),
              IconButton(tooltip: 'Editar', onPressed: () => _abrir(c), icon: const Icon(Icons.edit_outlined, size: 18)),
            ];
          },
          ficha: (i) {
            final c = lista[i];
            return Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  textoFuerte(context, '${c.codigo} · ${c.nombre}', lineas: 1),
                  textoSecundario(context, '${tipoCuentaLegible(c.tipo)}${c.activa ? '' : ' · inactiva'}'),
                ]),
              ),
              textoFuerte(context, formatearMoneda(c.saldo), lineas: 1),
              IconButton(tooltip: 'Editar', onPressed: () => _abrir(c), icon: const Icon(Icons.edit_outlined, size: 18)),
            ]);
          },
        ),
      ],
    );
  }
}

class _CuentaDialog extends StatefulWidget {
  const _CuentaDialog({this.cuenta});

  final CuentaContable? cuenta;

  @override
  State<_CuentaDialog> createState() => _CuentaDialogState();
}

class _CuentaDialogState extends State<_CuentaDialog> {
  final _form = GlobalKey<FormState>();
  late final _codigo = TextEditingController(text: widget.cuenta?.codigo);
  late final _nombre = TextEditingController(text: widget.cuenta?.nombre);
  late bool _activa = widget.cuenta?.activa ?? true;
  bool _guardando = false;
  String? _error;

  @override
  void dispose() {
    _codigo.dispose();
    _nombre.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    if (_guardando || !_form.currentState!.validate()) return;
    setState(() {
      _guardando = true;
      _error = null;
    });
    try {
      final c = await context.read<ContabilidadRepository>().guardarCuenta(
          widget.cuenta?.id, {'codigo': _codigo.text.trim(), 'nombre': _nombre.text.trim(), 'activa': _activa});
      if (mounted) Navigator.of(context).pop(c);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final nueva = widget.cuenta == null;
    return AlertDialog(
      title: Text(nueva ? 'Nueva cuenta' : 'Editar cuenta'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Form(
          key: _form,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            TextFormField(
              controller: _codigo,
              enabled: nueva && !_guardando,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(10)],
              decoration: const InputDecoration(labelText: 'Código', hintText: '6106'),
              validator: (v) => RegExp(r'^[1-6]\d{3,9}$').hasMatch(v ?? '') ? null : '4 a 10 dígitos; empieza con 1 a 6',
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _nombre,
              enabled: !_guardando,
              decoration: const InputDecoration(labelText: 'Nombre', hintText: 'Publicidad'),
              validator: (v) => (v == null || v.trim().length < 3) ? 'Campo obligatorio' : null,
            ),
            if (!nueva) ...[
              const SizedBox(height: 8),
              Casilla(
                valor: _activa,
                alCambiar: _guardando || widget.cuenta!.esSistema ? null : (v) => setState(() => _activa = v),
                texto: 'Activa',
                detalle: widget.cuenta!.esSistema
                    ? 'La usan las partidas automáticas: no se puede desactivar.'
                    : 'Una cuenta inactiva no recibe partidas nuevas.',
              ),
            ],
            if (_error != null) ...[const SizedBox(height: 12), InlineBanner.error(_error!)],
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: _guardando ? null : () => Navigator.of(context).pop(), child: const Text('Cancelar')),
        FilledButton(onPressed: _guardando ? null : _guardar, child: const Text('Guardar')),
      ],
    );
  }
}

/// Libro mayor de una cuenta: saldo inicial, movimientos del rango con saldo acumulado y saldo final.
class LibroMayorScreen extends StatefulWidget {
  const LibroMayorScreen({super.key, required this.cuenta});

  final CuentaContable cuenta;

  @override
  State<LibroMayorScreen> createState() => _LibroMayorScreenState();
}

class _LibroMayorScreenState extends State<LibroMayorScreen> with CargaDatos<LibroMayorScreen, LibroMayor> {
  DateTime _desde = inicioDeMes();
  DateTime _hasta = hoy();

  @override
  Future<LibroMayor> obtener() => context.read<ContabilidadRepository>().mayor(widget.cuenta.id, _desde, _hasta);

  @override
  Widget build(BuildContext context) {
    final m = datos;
    final movs = m?.movimientos ?? const <MovimientoMayor>[];

    return ModuloPage(
      titulo: 'Libro mayor · ${widget.cuenta.codigo} ${widget.cuenta.nombre}',
      subtitulo: tipoCuentaLegible(widget.cuenta.tipo),
      alRefrescar: recargar,
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
      ],
      children: [
        if (m != null)
          RejillaAdaptable(children: [
            KpiCard(titulo: 'Saldo inicial', valor: formatearMoneda(m.saldoInicial), icono: Icons.flag_outlined),
            KpiCard(titulo: 'Cargos (debe)', valor: formatearMoneda(m.totalDebe), icono: Icons.add_circle_outline, color: AppColors.accent),
            KpiCard(titulo: 'Abonos (haber)', valor: formatearMoneda(m.totalHaber), icono: Icons.remove_circle_outline, color: AppColors.warning),
            KpiCard(titulo: 'Saldo final', valor: formatearMoneda(m.saldoFinal), icono: Icons.account_balance_outlined),
          ]),
        TablaResponsiva(
          cargando: cargando,
          error: error,
          alReintentar: recargar,
          filas: movs.length,
          vacio: const EmptyState(icono: Icons.swap_horiz, titulo: 'Sin movimientos en este rango'),
          columnas: const [
            ColumnaTabla('Fecha', flex: 2),
            ColumnaTabla('Partida', flex: 5),
            ColumnaTabla('Debe', flex: 2, derecha: true),
            ColumnaTabla('Haber', flex: 2, derecha: true),
            ColumnaTabla('Saldo', flex: 2, derecha: true),
          ],
          celdas: (i) {
            final x = movs[i];
            return [
              textoSecundario(context, formatearDia(x.fecha)),
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                textoFuerte(context, '#${x.partida}', lineas: 1),
                textoSecundario(context, x.concepto, lineas: 2),
              ]),
              Text(x.debe > 0 ? formatearMoneda(x.debe) : ''),
              Text(x.haber > 0 ? formatearMoneda(x.haber) : ''),
              textoFuerte(context, formatearMoneda(x.saldo), lineas: 1),
            ];
          },
          ficha: (i) {
            final x = movs[i];
            return Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  textoFuerte(context, '#${x.partida} · ${formatearDia(x.fecha)}', lineas: 1),
                  textoSecundario(context, x.concepto, lineas: 2),
                ]),
              ),
              const SizedBox(width: 8),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text(x.debe > 0 ? '+ ${formatearMoneda(x.debe)}' : '- ${formatearMoneda(x.haber)}'),
                textoSecundario(context, 'Saldo ${formatearMoneda(x.saldo)}'),
              ]),
            ]);
          },
        ),
      ],
    );
  }
}
