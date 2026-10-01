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
import '../../data/models/pipeline.dart';
import '../shell/modulo_page.dart';
import 'mapa_ventas.dart';

enum _Desglose { productos, categorias, vendedores, clientes, formasPago }

/// Reportes de ventas: indicadores con comparación contra el período anterior, ventas por día y desgloses.
/// El vendedor ve solo sus ventas.
class ReporteVentasScreen extends StatefulWidget {
  const ReporteVentasScreen({super.key});

  @override
  State<ReporteVentasScreen> createState() => _ReporteVentasScreenState();
}

class _ReporteVentasScreenState extends State<ReporteVentasScreen> with CargaDatos<ReporteVentasScreen, ReporteVentas> {
  DateTime _desde = inicioDeMes();
  DateTime _hasta = hoy();
  _Desglose _desglose = _Desglose.productos;

  @override
  Future<ReporteVentas> obtener() => context.read<ReporteRepository>().ventas(_desde, _hasta);

  void _rango(DateTime desde, DateTime hasta) {
    setState(() {
      _desde = desde;
      _hasta = hasta;
    });
    recargar();
  }

  @override
  Widget build(BuildContext context) {
    final r = datos;
    final soloMias = context.watch<SessionController>().session?.puedeVender ?? false;
    final opciones = [
      _Desglose.productos,
      _Desglose.categorias,
      if (!soloMias) _Desglose.vendedores,
      _Desglose.clientes,
      _Desglose.formasPago,
    ];

    return ModuloPage(
      titulo: soloMias ? 'Reporte de mis ventas' : 'Reportes de ventas',
      subtitulo: 'Del ${formatearDia(_desde)} al ${formatearDia(_hasta)} · montos con IVA salvo que se indique',
      alRefrescar: recargar,
      acciones: [
        SelectorRango(desde: _desde, hasta: _hasta, alCambiar: _rango),
        MenuPeriodos(alCambiar: _rango),
      ],
      children: [
        if (cargando) const LinearProgressIndicator(),
        if (error != null) InlineBanner.error(error!),
        if (r != null) ...[
          _Indicadores(actual: r.resumen, anterior: r.anterior),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text('Ventas por día', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 16),
                GraficaBarras(barras: [
                  for (final (dia, facturas, total) in r.porDia)
                    (
                      r.porDia.length <= 7 ? diaCorto(dia) : '${dia.day}/${dia.month}',
                      total,
                      '${formatearDia(dia)}: ${formatearMoneda(total)} · $facturas ${facturas == 1 ? 'factura' : 'facturas'}',
                    ),
                ]),
              ]),
            ),
          ),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text('Ventas por departamento', style: Theme.of(context).textTheme.titleMedium),
                textoSecundario(context, 'El color indica cuánto se vendió: más oscuro, más ventas.'),
                textoSecundario(context, 'Según el lugar de entrega. Pasa el mouse o toca un departamento para ver su detalle.'),
                const SizedBox(height: 16),
                MapaVentas(datos: r.porDepartamento),
              ]),
            ),
          ),
          if (r.porEstado.isNotEmpty) _PorEtapa(estados: r.porEstado),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SegmentedButton<_Desglose>(
              segments: [
                for (final d in opciones)
                  ButtonSegment(
                    value: d,
                    label: Text(switch (d) {
                      _Desglose.productos => 'Productos',
                      _Desglose.categorias => 'Categorías',
                      _Desglose.vendedores => 'Vendedores',
                      _Desglose.clientes => 'Clientes',
                      _Desglose.formasPago => 'Formas de pago',
                    }),
                  ),
              ],
              selected: {opciones.contains(_desglose) ? _desglose : _Desglose.productos},
              showSelectedIcon: false,
              onSelectionChanged: (s) => setState(() => _desglose = s.first),
            ),
          ),
          _TablaDesglose(
            desglose: _desglose,
            filas: switch (_desglose) {
              _Desglose.productos => r.porProducto,
              _Desglose.categorias => r.porCategoria,
              _Desglose.vendedores => r.porVendedor,
              _Desglose.clientes => r.porCliente,
              _Desglose.formasPago => r.porFormaPago,
            },
          ),
        ],
      ],
    );
  }
}

class _Indicadores extends StatelessWidget {
  const _Indicadores({required this.actual, required this.anterior});

  final ResumenVentas actual;
  final ResumenVentas anterior;

  /// "▲ 12.5 % vs. período anterior".
  static String? _variacion(double actual, double anterior) {
    if (anterior == 0) return actual == 0 ? null : 'Sin ventas en el período anterior';
    final v = (actual - anterior) / anterior * 100;
    return '${v >= 0 ? '▲' : '▼'} ${v.abs().toStringAsFixed(1)} % vs. período anterior';
  }

  @override
  Widget build(BuildContext context) {
    return RejillaAdaptable(anchoMinimo: 250, children: [
      KpiCard(
        titulo: 'Ventas',
        valor: formatearMoneda(actual.total),
        detalle: _variacion(actual.total, anterior.total),
        icono: Icons.point_of_sale,
        color: AppColors.accent,
      ),
      KpiCard(
        titulo: 'Facturas',
        valor: formatearNumero(actual.facturas),
        detalle: '${formatearNumero(actual.unidades)} unidades vendidas',
        icono: Icons.receipt_long_outlined,
      ),
      KpiCard(
        titulo: 'Ticket promedio',
        valor: formatearMoneda(actual.ticketPromedio),
        detalle: _variacion(actual.ticketPromedio, anterior.ticketPromedio),
        icono: Icons.shopping_bag_outlined,
        color: const Color(0xFF6A4C93),
      ),
      KpiCard(
        titulo: 'Utilidad bruta (sin IVA)',
        valor: formatearMoneda(actual.utilidadBruta),
        detalle: 'Margen ${actual.margen.toStringAsFixed(1)} % · costo ${formatearMoneda(actual.costo)}',
        icono: Icons.trending_up,
        color: AppColors.success,
      ),
      KpiCard(
        titulo: 'Ventas sin IVA',
        valor: formatearMoneda(actual.baseImponible),
        detalle: 'Base imponible',
        icono: Icons.calculate_outlined,
      ),
      KpiCard(
        titulo: 'IVA cobrado',
        valor: formatearMoneda(actual.iva),
        detalle: 'Débito fiscal por pagar a la SAT',
        icono: Icons.account_balance_outlined,
        color: AppColors.warning,
      ),
    ]);
  }
}

class _TablaDesglose extends StatelessWidget {
  const _TablaDesglose({required this.desglose, required this.filas});

  final _Desglose desglose;
  final List<FilaReporte> filas;

  @override
  Widget build(BuildContext context) {
    final conUtilidad = desglose != _Desglose.clientes && desglose != _Desglose.formasPago;
    final conMargen = desglose == _Desglose.productos;
    final porUnidades = desglose == _Desglose.productos || desglose == _Desglose.categorias;
    final total = filas.fold<double>(0, (s, f) => s + f.total);

    Widget participacion(FilaReporte f) => Row(children: [
          Expanded(child: BarraParticipacion(porcentaje: f.participacion)),
          const SizedBox(width: 8),
          SizedBox(width: 48, child: textoSecundario(context, '${f.participacion.toStringAsFixed(1)} %')),
        ]);

    return TablaResponsiva(
      filas: filas.length,
      anchoTabla: 820,
      vacio: const EmptyState(icono: Icons.insights_outlined, titulo: 'No hay ventas en este período'),
      columnas: [
        ColumnaTabla(switch (desglose) {
          _Desglose.productos => 'Producto',
          _Desglose.categorias => 'Categoría',
          _Desglose.vendedores => 'Vendedor',
          _Desglose.clientes => 'Cliente',
          _Desglose.formasPago => 'Forma de pago',
        }, flex: 5),
        ColumnaTabla(porUnidades ? 'Unidades' : 'Facturas', flex: 2, derecha: true),
        const ColumnaTabla('Ventas', flex: 3, derecha: true),
        if (conUtilidad) const ColumnaTabla('Utilidad', flex: 3, derecha: true),
        if (conMargen) const ColumnaTabla('Margen', flex: 2, derecha: true),
        const ColumnaTabla('Participación', flex: 4),
      ],
      celdas: (i) {
        final f = filas[i];
        return [
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              SizedBox(width: 28, child: textoSecundario(context, '${i + 1}.')),
              Expanded(child: textoFuerte(context, f.titulo, lineas: 1)),
            ]),
            if (f.detalle != null)
              Padding(padding: const EdgeInsets.only(left: 28), child: textoSecundario(context, f.detalle!, lineas: 1)),
          ]),
          Text(formatearNumero(porUnidades ? f.cantidad : f.facturas)),
          textoFuerte(context, formatearMoneda(f.total), lineas: 1),
          if (conUtilidad) Text(formatearMoneda(f.utilidad ?? 0)),
          if (conMargen) textoSecundario(context, '${(f.margen ?? 0).toStringAsFixed(1)} %'),
          participacion(f),
        ];
      },
      ficha: (i) {
        final f = filas[i];
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(child: textoFuerte(context, '${i + 1}. ${f.titulo}', lineas: 1)),
            const SizedBox(width: 8),
            textoFuerte(context, formatearMoneda(f.total), lineas: 1),
          ]),
          textoSecundario(
              context,
              [
                if (f.detalle != null) f.detalle!,
                porUnidades ? '${f.cantidad} u.' : '${f.facturas} facturas',
                if (conUtilidad) 'utilidad ${formatearMoneda(f.utilidad ?? 0)}',
              ].join(' · ')),
          const SizedBox(height: 6),
          participacion(f),
        ]);
      },
      pie: FilaValor('Total', formatearMoneda(total), destacado: true),
    );
  }
}

/// Cuántas ventas del período hay en cada etapa del pipeline.
class _PorEtapa extends StatelessWidget {
  const _PorEtapa({required this.estados});

  final List<VentaEstado> estados;

  @override
  Widget build(BuildContext context) {
    final total = estados.fold<int>(0, (s, e) => s + e.facturas);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Ventas por etapa del pipeline', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 14),
          // Barra apilada: proporción de ventas en cada etapa.
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: SizedBox(
              height: 14,
              child: Row(children: [
                for (final e in estados)
                  if (e.facturas > 0)
                    Expanded(flex: e.facturas, child: ColoredBox(color: EstadosVenta.color(e.estado), child: const SizedBox.expand())),
                if (total == 0) const Expanded(child: ColoredBox(color: AppColors.border, child: SizedBox.expand())),
              ]),
            ),
          ),
          const SizedBox(height: 14),
          Wrap(spacing: 20, runSpacing: 10, children: [
            for (final e in estados)
              Row(mainAxisSize: MainAxisSize.min, children: [
                Container(width: 10, height: 10, decoration: BoxDecoration(color: EstadosVenta.color(e.estado), shape: BoxShape.circle)),
                const SizedBox(width: 6),
                Flexible(
                  child: Text.rich(
                    TextSpan(children: [
                      TextSpan(text: '${e.nombre}: '),
                      TextSpan(text: '${e.facturas}', style: const TextStyle(fontWeight: FontWeight.w700)),
                      TextSpan(text: ' · ${formatearMoneda(e.total)}', style: const TextStyle(color: AppColors.textSecondary)),
                    ]),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ]),
          ]),
        ]),
      ),
    );
  }
}
