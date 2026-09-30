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

  void _periodo(String p) {
    final h = hoy();
    switch (p) {
      case 'hoy':
        _rango(h, h);
      case 'semana':
        _rango(h.subtract(Duration(days: h.weekday - 1)), h);
      case 'mes':
        _rango(inicioDeMes(h), h);
      case 'mesAnterior':
        final inicio = DateTime(h.year, h.month - 1, 1);
        _rango(inicio, DateTime(h.year, h.month, 0));
      case 'anio':
        _rango(DateTime(h.year, 1, 1), h);
    }
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
        PopupMenuButton<String>(
          tooltip: 'Períodos rápidos',
          onSelected: _periodo,
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'hoy', child: Text('Hoy')),
            PopupMenuItem(value: 'semana', child: Text('Esta semana')),
            PopupMenuItem(value: 'mes', child: Text('Este mes')),
            PopupMenuItem(value: 'mesAnterior', child: Text('Mes anterior')),
            PopupMenuItem(value: 'anio', child: Text('En lo que va del año')),
          ],
          icon: const Icon(Icons.tune),
        ),
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
