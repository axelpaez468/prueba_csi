import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/network/api_exception.dart';
import '../../core/theme/app_theme.dart';
import '../../core/util/formatters.dart';
import '../../core/widgets/app_shell.dart';
import '../../core/widgets/erp_widgets.dart';
import '../../data/models/erp.dart';
import '../../data/repositories/erp_repositories.dart';
import '../shell/modulo_page.dart';

enum _Reporte { resultados, balanceGeneral, comprobacion }

/// Estados financieros: estado de resultados, balance general y balance de comprobación.
class ReportesScreen extends StatefulWidget {
  const ReportesScreen({super.key});

  @override
  State<ReportesScreen> createState() => _ReportesScreenState();
}

class _ReportesScreenState extends State<ReportesScreen> {
  _Reporte _reporte = _Reporte.resultados;
  DateTime _desde = inicioDeMes();
  DateTime _hasta = hoy();
  Object? _datos;
  bool _cargando = true;
  String? _error;

  ContabilidadRepository get _repo => context.read<ContabilidadRepository>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _cargar());
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final r = switch (_reporte) {
        _Reporte.resultados => await _repo.estadoResultados(_desde, _hasta),
        _Reporte.balanceGeneral => await _repo.balanceGeneral(_hasta),
        _Reporte.comprobacion => await _repo.balanceComprobacion(_desde, _hasta),
      };
      if (mounted) setState(() => _datos = r);
    } on UnauthorizedException {
      // La app vuelve al login.
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final datos = _datos;
    return ModuloPage(
      titulo: 'Estados financieros',
      subtitulo: switch (_reporte) {
        _Reporte.balanceGeneral => 'Balance general al ${formatearDia(_hasta)}',
        _ => 'Del ${formatearDia(_desde)} al ${formatearDia(_hasta)}',
      },
      alRefrescar: _cargar,
      acciones: [
        if (_reporte == _Reporte.balanceGeneral)
          SelectorFecha(
            fecha: _hasta,
            alCambiar: (f) {
              setState(() => _hasta = f);
              _cargar();
            },
          )
        else
          SelectorRango(
            desde: _desde,
            hasta: _hasta,
            alCambiar: (d, h) {
              setState(() {
                _desde = d;
                _hasta = h;
              });
              _cargar();
            },
          ),
      ],
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SegmentedButton<_Reporte>(
            segments: const [
              ButtonSegment(value: _Reporte.resultados, label: Text('Estado de resultados')),
              ButtonSegment(value: _Reporte.balanceGeneral, label: Text('Balance general')),
              ButtonSegment(value: _Reporte.comprobacion, label: Text('Comprobación')),
            ],
            selected: {_reporte},
            showSelectedIcon: false,
            onSelectionChanged: (s) {
              setState(() {
                _reporte = s.first;
                _datos = null;
              });
              _cargar();
            },
          ),
        ),
        if (_cargando) const LinearProgressIndicator(),
        if (_error != null) InlineBanner.error(_error!),
        if (datos is EstadoResultados) _EstadoResultadosView(datos),
        if (datos is BalanceGeneral) _BalanceGeneralView(datos),
        if (datos is BalanceComprobacion) _ComprobacionView(datos),
      ],
    );
  }
}

class _Seccion extends StatelessWidget {
  const _Seccion(this.titulo, this.renglones, this.total, {this.extra = const []});

  final String titulo;
  final List<Renglon> renglones;
  final double total;
  final List<Widget> extra;

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(titulo.toUpperCase(), style: estiloEncabezadoTabla(context)),
      const SizedBox(height: 6),
      if (renglones.isEmpty && extra.isEmpty) textoSecundario(context, 'Sin movimientos'),
      for (final r in renglones) FilaValor('${r.codigo}  ${r.cuenta}', formatearMoneda(r.monto)),
      ...extra,
      const Divider(),
      FilaValor('Total ${titulo.toLowerCase()}', formatearMoneda(total), destacado: true),
      const SizedBox(height: 12),
    ]);
  }
}

class _EstadoResultadosView extends StatelessWidget {
  const _EstadoResultadosView(this.er);

  final EstadoResultados er;

  @override
  Widget build(BuildContext context) {
    final ganancia = er.utilidadNeta >= 0;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _Seccion('Ingresos', er.ingresos, er.totalIngresos),
          _Seccion('Costos', er.costos, er.totalCostos),
          FilaValor('Utilidad bruta', formatearMoneda(er.utilidadBruta), destacado: true),
          const SizedBox(height: 16),
          _Seccion('Gastos', er.gastos, er.totalGastos),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: ganancia ? AppColors.successBg : AppColors.dangerBg,
              borderRadius: BorderRadius.circular(10),
            ),
            child: FilaValor(ganancia ? 'Utilidad neta' : 'Pérdida neta', formatearMoneda(er.utilidadNeta),
                destacado: true, color: ganancia ? AppColors.success : AppColors.danger),
          ),
          const SizedBox(height: 8),
          textoSecundario(context, 'Ingresos sin IVA. El IVA cobrado es un pasivo (IVA por pagar), no un ingreso.'),
        ]),
      ),
    );
  }
}

class _BalanceGeneralView extends StatelessWidget {
  const _BalanceGeneralView(this.bg);

  final BalanceGeneral bg;

  @override
  Widget build(BuildContext context) {
    final activos = _Seccion('Activo', bg.activos, bg.totalActivos);
    final pasivoCapital = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _Seccion('Pasivo', bg.pasivos, bg.totalPasivos),
      _Seccion('Capital', bg.capital, bg.totalCapital,
          extra: [FilaValor('Resultado del ejercicio', formatearMoneda(bg.resultadoDelEjercicio))]),
      FilaValor('Total pasivo y capital', formatearMoneda(bg.totalPasivoYCapital), destacado: true),
    ]);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          LayoutBuilder(builder: (context, c) => c.maxWidth >= 760
              ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(child: activos),
                  const SizedBox(width: 32),
                  Expanded(child: pasivoCapital),
                ])
              : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [activos, pasivoCapital])),
          const SizedBox(height: 12),
          _Cuadre(bg.cuadra, 'Activo = Pasivo + Capital'),
        ]),
      ),
    );
  }
}

class _ComprobacionView extends StatelessWidget {
  const _ComprobacionView(this.bc);

  final BalanceComprobacion bc;

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      TablaResponsiva(
        filas: bc.filas.length,
        anchoTabla: 820,
        vacio: const EmptyState(icono: Icons.balance, titulo: 'Sin movimientos en este rango'),
        columnas: const [
          ColumnaTabla('Cuenta', flex: 5),
          ColumnaTabla('Debe', flex: 2, derecha: true),
          ColumnaTabla('Haber', flex: 2, derecha: true),
          ColumnaTabla('Saldo deudor', flex: 2, derecha: true),
          ColumnaTabla('Saldo acreedor', flex: 2, derecha: true),
        ],
        celdas: (i) {
          final f = bc.filas[i];
          String m(double v) => v == 0 ? '' : formatearMoneda(v);
          return [
            Text('${f.codigo}  ${f.cuenta}', overflow: TextOverflow.ellipsis),
            Text(m(f.debe)),
            Text(m(f.haber)),
            textoFuerte(context, m(f.saldoDeudor), lineas: 1),
            textoFuerte(context, m(f.saldoAcreedor), lineas: 1),
          ];
        },
        ficha: (i) {
          final f = bc.filas[i];
          return Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                textoFuerte(context, '${f.codigo} ${f.cuenta}', lineas: 1),
                textoSecundario(context, 'Debe ${formatearMoneda(f.debe)} · Haber ${formatearMoneda(f.haber)}'),
              ]),
            ),
            textoFuerte(
                context,
                f.saldoDeudor > 0 ? '${formatearMoneda(f.saldoDeudor)} D' : '${formatearMoneda(f.saldoAcreedor)} A',
                lineas: 1),
          ]);
        },
        pie: Column(children: [
          FilaValor('Sumas: debe / haber', '${formatearMoneda(bc.totalDebe)} / ${formatearMoneda(bc.totalHaber)}'),
          FilaValor('Saldos: deudor / acreedor', '${formatearMoneda(bc.totalDeudor)} / ${formatearMoneda(bc.totalAcreedor)}'),
        ]),
      ),
      const SizedBox(height: 12),
      _Cuadre(bc.cuadra, 'Sumas y saldos iguales'),
    ]);
  }
}

class _Cuadre extends StatelessWidget {
  const _Cuadre(this.cuadra, this.regla);

  final bool cuadra;
  final String regla;

  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.centerLeft,
        child: cuadra
            ? StatusPill(texto: 'Cuadra: $regla', color: AppColors.success, fondo: AppColors.successBg, icono: Icons.check_circle)
            : StatusPill(texto: 'No cuadra: $regla', color: AppColors.danger, fondo: AppColors.dangerBg, icono: Icons.error),
      );
}
