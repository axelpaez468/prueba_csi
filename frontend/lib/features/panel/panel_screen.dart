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
      encabezado: session == null
          ? null
          : _Bienvenida(nombre: nombre, rol: session.nombreRol, pendientes: p?.ordenesPendientes, alertas: p?.bajoMinimo.length,
              cargando: cargando, alActualizar: recargar),
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
        if (session != null) _AccesosRapidos(modulos: modulosDe(session).where((m) => m.grupo != 'Inicio').toList()),
      ],
    );
  }
}

class _GraficaSemana extends StatelessWidget {
  const _GraficaSemana(this.dias);

  final List<(DateTime, double)> dias;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Ventas de los últimos 7 días', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 20),
            GraficaBarras(barras: [
              for (final (dia, total) in dias) (diaCorto(dia), total, '${formatearDia(dia)}: ${formatearMoneda(total)}'),
            ]),
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

/// Encabezado del panel: saludo, rol, fecha y avisos del día sobre el degradado de marca.
class _Bienvenida extends StatelessWidget {
  const _Bienvenida({
    required this.nombre,
    required this.rol,
    required this.pendientes,
    required this.alertas,
    required this.cargando,
    required this.alActualizar,
  });

  final String nombre;
  final String rol;
  final int? pendientes;
  final int? alertas;
  final bool cargando;
  final Future<void> Function() alActualizar;

  @override
  Widget build(BuildContext context) {
    final compacto = Breakpoints.esCompacto(context);
    final margen = compacto ? 16.0 : 24.0;
    final hora = DateTime.now().hour;
    final saludo = hora < 12 ? 'Buenos días' : hora < 19 ? 'Buenas tardes' : 'Buenas noches';

    Widget chip(IconData icono, String texto) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(99),
            border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icono, size: 15, color: Colors.white),
            const SizedBox(width: 6),
            Flexible(
              child: Text(texto,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500)),
            ),
          ]),
        );

    return Padding(
      padding: EdgeInsets.fromLTRB(margen, margen, margen, 20),
      child: Container(
        padding: EdgeInsets.all(compacto ? 20 : 28),
        decoration: BoxDecoration(
          gradient: AppColors.degradado,
          borderRadius: BorderRadius.circular(20),
          boxShadow: const [BoxShadow(color: Color(0x332450C8), blurRadius: 24, offset: Offset(0, 10))],
        ),
        child: Stack(children: [
          // Figura decorativa sutil a la derecha.
          Positioned(
            right: -20,
            top: -30,
            child: Icon(Icons.hub_outlined, size: compacto ? 120 : 180, color: Colors.white.withValues(alpha: 0.06)),
          ),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(fechaLarga(DateTime.now()).toUpperCase(),
                style: const TextStyle(color: Color(0xFFB9C8F5), fontSize: 12, letterSpacing: 1.2, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Text('$saludo, $nombre',
                style: TextStyle(color: Colors.white, fontSize: compacto ? 24 : 30, fontWeight: FontWeight.w800, letterSpacing: -0.5)),
            const SizedBox(height: 4),
            Text('Este es el resumen de tu negocio · $rol',
                style: const TextStyle(color: Color(0xFFD5DEF8), fontSize: 14)),
            const SizedBox(height: 18),
            Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
              if (pendientes != null)
                chip(Icons.local_shipping_outlined,
                    '$pendientes ${pendientes == 1 ? 'orden de compra pendiente' : 'órdenes de compra pendientes'}'),
              if (alertas != null)
                chip(Icons.warning_amber_rounded, '$alertas ${alertas == 1 ? 'producto por reabastecer' : 'productos por reabastecer'}'),
              TextButton.icon(
                style: TextButton.styleFrom(foregroundColor: Colors.white),
                onPressed: cargando ? null : alActualizar,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Actualizar'),
              ),
            ]),
          ]),
        ]),
      ),
    );
  }
}
