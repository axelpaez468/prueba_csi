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
import '../shell/modulos.dart';

/// Inicio de administración, bodega, compras y contabilidad: indicadores y accesos a los módulos.
class PanelScreen extends StatefulWidget {
  const PanelScreen({super.key});

  @override
  State<PanelScreen> createState() => _PanelScreenState();
}

class _PanelScreenState extends State<PanelScreen> with CargaDatos<PanelScreen, Panel> {
  @override
  Future<Panel> obtener() => context.read<PanelRepository>().resumen();

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionController>().session;
    final p = datos;
    final nombre = session?.username.split(' ').first ?? '';

    return ModuloPage(
      esInicio: true,
      titulo: 'Hola, $nombre',
      subtitulo: session == null ? null : '${session.nombreRol} · ${fechaLarga(DateTime.now())}',
      alRefrescar: recargar,
      acciones: [
        OutlinedButton.icon(
          onPressed: cargando ? null : recargar,
          icon: const Icon(Icons.refresh, size: 18),
          label: const Text('Actualizar'),
        ),
      ],
      children: [
        if (error != null) InlineBanner.error(error!),
        if (cargando && p == null) const LinearProgressIndicator(),
        if (p != null) ...[
          RejillaAdaptable(children: [
            KpiCard(
              titulo: 'Ventas de hoy',
              valor: formatearMoneda(p.ventasHoy),
              detalle: '${p.cantidadVentasHoy} ${p.cantidadVentasHoy == 1 ? 'factura' : 'facturas'}',
              icono: Icons.point_of_sale,
              color: AppColors.accent,
            ),
            KpiCard(
              titulo: 'Ventas del mes',
              valor: formatearMoneda(p.ventasMes),
              detalle: 'Utilidad bruta ${formatearMoneda(p.utilidadBrutaMes)}',
              icono: Icons.trending_up,
            ),
            KpiCard(
              titulo: 'Valor del inventario',
              valor: formatearMoneda(p.valorInventario),
              detalle: 'Al costo promedio, sin IVA',
              icono: Icons.inventory_2_outlined,
              color: const Color(0xFF6A4C93),
            ),
            KpiCard(
              titulo: 'Compras del mes',
              valor: formatearMoneda(p.comprasMes),
              detalle: '${p.ordenesPendientes} ${p.ordenesPendientes == 1 ? 'orden pendiente' : 'órdenes pendientes'}',
              icono: Icons.local_shipping_outlined,
              color: AppColors.warning,
            ),
          ]),
          LayoutBuilder(builder: (context, c) {
            final grafica = _GraficaSemana(p.ventasSemana);
            final alertas = _BajoMinimo(p.bajoMinimo);
            return c.maxWidth >= 900
                ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(flex: 3, child: grafica),
                    const SizedBox(width: 16),
                    Expanded(flex: 2, child: alertas),
                  ])
                : Column(children: [grafica, const SizedBox(height: 16), alertas]);
          }),
        ],
        if (session != null) _AccesosRapidos(modulos: modulosDe(session).where((m) => m.titulo != 'Inicio').toList()),
      ],
    );
  }
}

class _GraficaSemana extends StatelessWidget {
  const _GraficaSemana(this.dias);

  final List<(DateTime, double)> dias;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final maximo = dias.fold<double>(0, (m, d) => d.$2 > m ? d.$2 : m);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Ventas de los últimos 7 días', style: theme.textTheme.titleMedium),
            const SizedBox(height: 20),
            SizedBox(
              height: 180,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (final (dia, total) in dias)
                    Expanded(
                      child: Tooltip(
                        message: '${formatearDia(dia)}: ${formatearMoneda(total)}',
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Expanded(
                              child: Align(
                                alignment: Alignment.bottomCenter,
                                child: FractionallySizedBox(
                                  heightFactor: maximo == 0 ? 0.02 : (total / maximo).clamp(0.02, 1.0),
                                  child: Container(
                                    margin: const EdgeInsets.symmetric(horizontal: 6),
                                    decoration: BoxDecoration(
                                      color: total > 0 ? AppColors.primary : AppColors.border,
                                      borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            FittedBox(child: textoSecundario(context, diaCorto(dia))),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BajoMinimo extends StatelessWidget {
  const _BajoMinimo(this.productos);

  final List<ProductoAlerta> productos;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              const Icon(Icons.warning_amber_rounded, color: AppColors.warning, size: 20),
              const SizedBox(width: 8),
              Expanded(child: Text('Productos por reabastecer', style: theme.textTheme.titleMedium)),
            ]),
            const SizedBox(height: 12),
            if (productos.isEmpty)
              textoSecundario(context, 'Todos los productos están por encima de su stock mínimo.')
            else
              for (final p in productos)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        textoFuerte(context, p.nombre, lineas: 1),
                        textoSecundario(context, '${p.codigo} · mínimo ${p.stockMinimo}'),
                      ]),
                    ),
                    StatusPill(
                      texto: '${p.stock} en existencia',
                      color: p.stock == 0 ? AppColors.danger : AppColors.warning,
                      fondo: p.stock == 0 ? AppColors.dangerBg : AppColors.warningBg,
                    ),
                  ]),
                ),
          ],
        ),
      ),
    );
  }
}

class _AccesosRapidos extends StatelessWidget {
  const _AccesosRapidos({required this.modulos});

  final List<Modulo> modulos;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 12),
          child: Text('Módulos', style: theme.textTheme.titleMedium),
        ),
        RejillaAdaptable(
          anchoMinimo: 220,
          children: [
            for (final m in modulos)
              Card(
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () => abrirModulo(context, m),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(children: [
                      Icon(m.icono, color: AppColors.primary),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          textoFuerte(context, m.titulo, lineas: 1),
                          textoSecundario(context, m.descripcion, lineas: 1),
                        ]),
                      ),
                      const Icon(Icons.chevron_right, color: AppColors.textSecondary),
                    ]),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}
