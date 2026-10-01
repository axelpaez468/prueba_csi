import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/network/api_exception.dart';
import '../../core/security/permisos.dart';
import '../../core/theme/app_theme.dart';
import '../../core/util/formatters.dart';
import '../../core/widgets/app_shell.dart';
import '../../core/widgets/erp_widgets.dart';
import '../../data/models/pipeline.dart';
import '../../data/models/pronostico.dart';
import '../../data/repositories/erp_repositories.dart';
import '../auth/session_controller.dart';
import '../shell/modulo_page.dart';
import '../ventas/pipeline_widgets.dart';
import 'graficas_pronostico.dart';

/// Pipeline y pronóstico (forecast) de ventas. Cada etapa tiene una probabilidad de cierre; lo esperado de una
/// etapa es su total por esa probabilidad, y el pronóstico es lo cerrado más lo esperado de las etapas abiertas.
class PronosticoScreen extends StatefulWidget {
  const PronosticoScreen({super.key});

  @override
  State<PronosticoScreen> createState() => _PronosticoScreenState();
}

class _PronosticoScreenState extends State<PronosticoScreen> with CargaDatos<PronosticoScreen, Pronostico> {
  DateTime _desde = inicioDeMes();
  DateTime _hasta = hoy();

  ReporteRepository get _repo => context.read<ReporteRepository>();

  @override
  Future<Pronostico> obtener() => _repo.pronostico(_desde, _hasta);

  void _rango(DateTime desde, DateTime hasta) {
    setState(() {
      _desde = desde;
      _hasta = hasta;
    });
    recargar();
  }

  Future<void> _editarProbabilidades(Pronostico p) async {
    final nuevas = await showDialog<Map<String, double>>(
      context: context,
      builder: (_) => _DialogoProbabilidades(actuales: {for (final e in p.etapas) e.estado: e.probabilidad}),
    );
    if (nuevas == null || !mounted) return;
    try {
      final mensaje = await _repo.guardarProbabilidades(nuevas);
      if (mounted) avisar(context, mensaje);
      await recargar();
    } on ApiException catch (e) {
      if (mounted) avisar(context, e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = datos;
    final session = context.watch<SessionController>().session;
    final soloMias = session?.puedeVender ?? false;
    final puedeEditar = session?.esAdmin ?? false;
    final ancho = MediaQuery.sizeOf(context).width;

    final embudo = _Tarjeta(
      titulo: 'Embudo del pipeline',
      ayuda: 'Ventas y monto en cada etapa. El número es la cantidad de ventas.',
      child: p == null ? const SizedBox() : EmbudoPipeline(etapas: p.etapas),
    );
    final porEtapa = _Tarjeta(
      titulo: 'Total vs. esperado por etapa',
      ayuda: 'Arriba, la probabilidad de cierre de la etapa.',
      child: p == null ? const SizedBox() : GraficaEtapas(etapas: p.etapas),
    );

    return ModuloPage(
      titulo: soloMias ? 'Mi pipeline y pronóstico' : 'Pipeline y pronóstico',
      subtitulo: 'Ventas registradas del ${formatearDia(_desde)} al ${formatearDia(_hasta)} · montos con IVA',
      maxWidth: 1320,
      alRefrescar: recargar,
      acciones: [
        SelectorRango(desde: _desde, hasta: _hasta, alCambiar: _rango),
        MenuPeriodos(alCambiar: _rango),
      ],
      children: [
        if (cargando) const LinearProgressIndicator(),
        if (error != null) InlineBanner.error(error!),
        if (p != null) ...[
          RejillaAdaptable(
            anchoMinimo: 250,
            children: [
              KpiCard(
                titulo: 'Pronóstico del período',
                valor: formatearMoneda(p.pronostico),
                detalle: 'Cerrado + esperado de las abiertas',
                icono: Icons.trending_up,
              ),
              KpiCard(
                titulo: 'Cerrado',
                valor: formatearMoneda(p.cerrado),
                detalle: '${p.facturasCerradas} ${p.facturasCerradas == 1 ? 'venta entregada' : 'ventas entregadas'} y cobradas',
                icono: Icons.task_alt,
                color: ColoresPronostico.cerrado,
              ),
              KpiCard(
                titulo: 'Esperado por cerrar',
                valor: formatearMoneda(p.ponderadoAbierto),
                detalle: 'De ${formatearMoneda(p.abierto)} abierto · prob. media ${formatearPorcentaje(p.probabilidadAbiertas)}',
                icono: Icons.hourglass_bottom,
                color: const Color(0xFF6366F1),
              ),
              KpiCard(
                titulo: 'Avance de cierre',
                valor: formatearPorcentaje(p.avanceCierre),
                detalle: 'Del pronóstico ya está cerrado',
                icono: Icons.donut_large,
                color: AppColors.warning,
              ),
            ],
          ),
          _Tarjeta(
            titulo: 'Cerrado vs. pronóstico',
            ayuda: 'Las tres barras usan la misma escala.',
            child: GraficaCerradoVsPronostico(pronostico: p),
          ),
          if (ancho >= 1000)
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: embudo),
                  const SizedBox(width: 16),
                  Expanded(child: porEtapa),
                ],
              ),
            )
          else ...[
            embudo,
            porEtapa,
          ],
          _Tarjeta(
            titulo: switch (p.agrupacion) {
              'MES' => 'Tendencia por mes',
              'SEMANA' => 'Tendencia por semana',
              _ => 'Tendencia por día',
            },
            ayuda: 'Según la fecha de la venta. Pasa el mouse o toca una barra para ver el detalle.',
            child: GraficaTendencia(tramos: p.tendencia, agrupacion: p.agrupacion),
          ),
          _TablaEtapas(pronostico: p, puedeEditar: puedeEditar, alEditar: () => _editarProbabilidades(p)),
          if (!soloMias) _TablaVendedores(filas: p.porVendedor),
        ],
      ],
    );
  }
}

class _Tarjeta extends StatelessWidget {
  const _Tarjeta({required this.titulo, required this.child, this.ayuda, this.accion});

  final String titulo;
  final String? ayuda;
  final Widget? accion;
  final Widget child;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(titulo, style: Theme.of(context).textTheme.titleMedium),
                    if (ayuda != null) textoSecundario(context, ayuda!),
                  ],
                ),
              ),
              ?accion,
            ],
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    ),
  );
}

/// Tabla del cálculo: total de cada etapa × su probabilidad = esperado. El administrador cambia las probabilidades.
class _TablaEtapas extends StatelessWidget {
  const _TablaEtapas({required this.pronostico, required this.puedeEditar, required this.alEditar});

  final Pronostico pronostico;
  final bool puedeEditar;
  final VoidCallback alEditar;

  @override
  Widget build(BuildContext context) {
    final p = pronostico;
    final etapas = p.etapas;
    final editado = p.actualizadoEn == null
        ? 'Valores iniciales del sistema.'
        : 'Cambiadas el ${formatearFecha(p.actualizadoEn!)}${p.actualizadoPor == null ? '' : ' por ${p.actualizadoPor}'}.';

    Widget probabilidad(EtapaPronostico e) => Row(
      children: [
        Expanded(
          child: BarraParticipacion(porcentaje: e.probabilidad, color: EstadosVenta.color(e.estado)),
        ),
        const SizedBox(width: 8),
        SizedBox(width: 48, child: textoFuerte(context, formatearPorcentaje(e.probabilidad), lineas: 1)),
      ],
    );

    return _Tarjeta(
      titulo: 'Probabilidad de cierre por etapa',
      ayuda: 'Esperado = total de la etapa × probabilidad. $editado',
      accion: puedeEditar
          ? Padding(
              padding: const EdgeInsets.only(left: 8),
              child: OutlinedButton.icon(
                onPressed: alEditar,
                icon: const Icon(Icons.tune, size: 18),
                label: const Text('Editar'),
              ),
            )
          : null,
      child: TablaResponsiva(
        filas: etapas.length,
        anchoTabla: 760,
        columnas: const [
          ColumnaTabla('Etapa', flex: 3),
          ColumnaTabla('Probabilidad', flex: 3),
          ColumnaTabla('Ventas', flex: 1, derecha: true),
          ColumnaTabla('Total', flex: 2, derecha: true),
          ColumnaTabla('Esperado', flex: 2, derecha: true),
        ],
        celdas: (i) {
          final e = etapas[i];
          return [
            Align(alignment: Alignment.centerLeft, child: PillEtapa(e.estado)),
            probabilidad(e),
            Text(formatearNumero(e.facturas)),
            Text(formatearMoneda(e.total)),
            textoFuerte(context, formatearMoneda(e.ponderado), lineas: 1),
          ];
        },
        ficha: (i) {
          final e = etapas[i];
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Align(alignment: Alignment.centerLeft, child: PillEtapa(e.estado)),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: textoSecundario(
                      context,
                      '${e.facturas} ventas · ${formatearMoneda(e.total)} × ${formatearPorcentaje(e.probabilidad)}',
                    ),
                  ),
                  const SizedBox(width: 8),
                  textoFuerte(context, formatearMoneda(e.ponderado), lineas: 1),
                ],
              ),
              const SizedBox(height: 6),
              probabilidad(e),
            ],
          );
        },
        pie: Column(
          children: [
            FilaValor('Cerrado (entregado, 100 %)', formatearMoneda(p.cerrado)),
            FilaValor('Esperado de las abiertas', formatearMoneda(p.ponderadoAbierto)),
            FilaValor('Pronóstico', formatearMoneda(p.pronostico), destacado: true),
          ],
        ),
      ),
    );
  }
}

class _TablaVendedores extends StatelessWidget {
  const _TablaVendedores({required this.filas});

  final List<PronosticoVendedor> filas;

  @override
  Widget build(BuildContext context) {
    Widget avance(PronosticoVendedor v) {
      final pct = v.pronostico == 0 ? 0.0 : v.cerrado / v.pronostico * 100;
      return Row(
        children: [
          Expanded(
            child: BarraParticipacion(porcentaje: pct, color: ColoresPronostico.cerrado),
          ),
          const SizedBox(width: 8),
          SizedBox(width: 48, child: textoSecundario(context, formatearPorcentaje(double.parse(pct.toStringAsFixed(1))))),
        ],
      );
    }

    return _Tarjeta(
      titulo: 'Pronóstico por vendedor',
      ayuda: 'Avance: qué parte de su pronóstico ya está cerrada.',
      child: TablaResponsiva(
        filas: filas.length,
        anchoTabla: 860,
        vacio: const EmptyState(icono: Icons.trending_up, titulo: 'No hay ventas en este período'),
        columnas: const [
          ColumnaTabla('Vendedor', flex: 3),
          ColumnaTabla('Ventas', flex: 1, derecha: true),
          ColumnaTabla('Cerrado', flex: 2, derecha: true),
          ColumnaTabla('Esperado', flex: 2, derecha: true),
          ColumnaTabla('Pronóstico', flex: 2, derecha: true),
          ColumnaTabla('Avance', flex: 3),
        ],
        celdas: (i) {
          final v = filas[i];
          return [
            textoFuerte(context, v.vendedor, lineas: 1),
            Text(formatearNumero(v.facturas)),
            Text(formatearMoneda(v.cerrado)),
            Text(formatearMoneda(v.ponderado)),
            textoFuerte(context, formatearMoneda(v.pronostico), lineas: 1),
            avance(v),
          ];
        },
        ficha: (i) {
          final v = filas[i];
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(child: textoFuerte(context, v.vendedor, lineas: 1)),
                  textoFuerte(context, formatearMoneda(v.pronostico), lineas: 1),
                ],
              ),
              textoSecundario(
                context,
                '${v.facturas} ventas · cerrado ${formatearMoneda(v.cerrado)} · esperado ${formatearMoneda(v.ponderado)}',
              ),
              const SizedBox(height: 6),
              avance(v),
            ],
          );
        },
      ),
    );
  }
}

/// Probabilidades con que arranca el sistema (espejo de backend/Domain/Pipeline.cs).
const _probabilidadInicial = {
  EstadosVenta.nuevo: 10.0,
  EstadosVenta.revisado: 25.0,
  EstadosVenta.autorizado: 50.0,
  EstadosVenta.despachado: 75.0,
  EstadosVenta.enCamino: 90.0,
  EstadosVenta.entregado: 100.0,
};

/// Editor de las probabilidades: de 5 en 5, sin bajar de una etapa a la siguiente; "Entregado" queda en 100 %.
class _DialogoProbabilidades extends StatefulWidget {
  const _DialogoProbabilidades({required this.actuales});

  final Map<String, double> actuales;

  @override
  State<_DialogoProbabilidades> createState() => _DialogoProbabilidadesState();
}

class _DialogoProbabilidadesState extends State<_DialogoProbabilidades> {
  late final Map<String, double> _valores = {
    for (final e in EstadosVenta.orden) e: e == EstadosVenta.entregado ? 100 : widget.actuales[e] ?? _probabilidadInicial[e]!,
  };

  /// Primera etapa con menos probabilidad que la anterior, o null si todo está en orden.
  String? get _error {
    for (var i = 1; i < EstadosVenta.orden.length; i++) {
      final (antes, ahora) = (EstadosVenta.orden[i - 1], EstadosVenta.orden[i]);
      if (_valores[ahora]! < _valores[antes]!) {
        return '"${EstadosVenta.nombre(ahora)}" no puede tener menos probabilidad que "${EstadosVenta.nombre(antes)}".';
      }
    }
    return null;
  }

  Widget _fila(BuildContext context, String e, bool angosto) {
    final slider = Slider(
      key: Key('probabilidad-$e'),
      value: _valores[e]!,
      max: 100,
      divisions: 20,
      label: formatearPorcentaje(_valores[e]!),
      activeColor: EstadosVenta.color(e),
      onChanged: e == EstadosVenta.entregado ? null : (v) => setState(() => _valores[e] = v),
    );
    final valor = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (e == EstadosVenta.entregado)
          const Padding(
            padding: EdgeInsets.only(right: 2),
            child: Icon(Icons.lock_outline, size: 14, color: AppColors.textSecondary),
          ),
        textoFuerte(context, formatearPorcentaje(_valores[e]!), lineas: 1),
      ],
    );
    // En celular el control va debajo del nombre de la etapa, para que tenga espacio.
    if (angosto) {
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Align(alignment: Alignment.centerLeft, child: PillEtapa(e)),
                ),
                valor,
              ],
            ),
            slider,
          ],
        ),
      );
    }
    return Row(
      children: [
        SizedBox(
          width: 120,
          child: Align(alignment: Alignment.centerLeft, child: PillEtapa(e)),
        ),
        Expanded(child: slider),
        SizedBox(
          width: 56,
          child: Align(
            alignment: Alignment.centerRight,
            child: FittedBox(fit: BoxFit.scaleDown, child: valor),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final error = _error;
    // MediaQuery y no LayoutBuilder: AlertDialog mide su contenido con dimensiones intrínsecas.
    final angosto = MediaQuery.sizeOf(context).width < 560;
    return AlertDialog(
      title: const Text('Probabilidad de cierre'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              textoSecundario(
                context,
                'Qué tan probable es que una venta en cada etapa termine entregada y cobrada. Una etapa más avanzada no puede tener menos probabilidad.',
              ),
              const SizedBox(height: 12),
              for (final e in EstadosVenta.orden) _fila(context, e, angosto),
              if (error != null) ...[const SizedBox(height: 8), InlineBanner.error(error)],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => setState(() => _valores.addAll(_probabilidadInicial)),
          child: const Text('Valores iniciales'),
        ),
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancelar')),
        FilledButton(
          onPressed: error == null ? () => Navigator.of(context).pop(Map.of(_valores)) : null,
          child: const Text('Guardar'),
        ),
      ],
    );
  }
}
