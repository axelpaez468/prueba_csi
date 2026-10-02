import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/security/permisos.dart';
import '../../core/theme/app_theme.dart';
import '../../core/util/formatters.dart';
import '../../core/widgets/app_shell.dart';
import '../../core/widgets/erp_widgets.dart';
import '../../data/models/erp.dart';
import '../../data/models/pedido.dart';
import '../../core/network/api_exception.dart';
import '../../data/models/pipeline.dart';
import '../../data/repositories/erp_repositories.dart';
import '../../data/repositories/pedido_repository.dart';
import '../auth/session_controller.dart';
import '../shell/modulo_page.dart';
import 'factura_view.dart';
import 'pipeline_widgets.dart';

/// Facturas emitidas en un rango de fechas. El vendedor ve las suyas; ADMIN y CONTADOR, todas.
class VentasScreen extends StatefulWidget {
  const VentasScreen({super.key});

  @override
  State<VentasScreen> createState() => _VentasScreenState();
}

class _VentasScreenState extends State<VentasScreen> with CargaDatos<VentasScreen, List<VentaResumen>> {
  DateTime _desde = inicioDeMes();
  DateTime _hasta = hoy();

  @override
  Future<List<VentaResumen>> obtener() => context.read<PedidoRepository>().listar(_desde, _hasta);

  void _abrir(VentaResumen v) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => VentaDetalleScreen(numero: v.numero)));

  @override
  Widget build(BuildContext context) {
    final lista = datos ?? const <VentaResumen>[];
    final total = lista.fold<double>(0, (s, v) => s + v.total);
    final soloMias = context.watch<SessionController>().session?.puedeVender ?? false;

    return ModuloPage(
      titulo: soloMias ? 'Mis ventas' : 'Ventas',
      subtitulo: '${lista.length} facturas · ${formatearMoneda(total)}',
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
        TablaResponsiva(
          cargando: cargando,
          error: error,
          alReintentar: recargar,
          filas: lista.length,
          alTocar: (i) => _abrir(lista[i]),
          vacio: const EmptyState(icono: Icons.receipt_long_outlined, titulo: 'No hay ventas en este rango'),
          columnas: [
            const ColumnaTabla('Factura', flex: 2),
            const ColumnaTabla('Fecha', flex: 2),
            const ColumnaTabla('Cliente', flex: 4),
            if (!soloMias) const ColumnaTabla('Vendedor', flex: 3),
            const ColumnaTabla('Entrega', flex: 2),
            const ColumnaTabla('Etapa', flex: 2),
            const ColumnaTabla('Total', flex: 2, derecha: true),
          ],
          celdas: (i) {
            final v = lista[i];
            return [
              textoFuerte(context, '${v.serie}-${v.numero}', lineas: 1),
              textoSecundario(context, formatearFecha(v.fecha)),
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                textoFuerte(context, v.clienteNombre, lineas: 1),
                textoSecundario(context, 'NIT ${v.clienteNit}'),
              ]),
              if (!soloMias) textoSecundario(context, v.vendedor, lineas: 1),
              textoSecundario(context, v.departamento ?? 'Mostrador', lineas: 1),
              PillEtapa(v.estado),
              textoFuerte(context, formatearMoneda(v.total), lineas: 1),
            ];
          },
          ficha: (i) {
            final v = lista[i];
            return Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  textoFuerte(context, 'Factura ${v.serie}-${v.numero} · ${v.clienteNombre}', lineas: 1),
                  textoSecundario(context,
                      '${formatearFecha(v.fecha)} · ${formaPagoLegible(v.formaPago)}${v.departamento == null ? '' : ' · ${v.departamento}'}'),
                  const SizedBox(height: 4),
                  PillEtapa(v.estado),
                ]),
              ),
              const SizedBox(width: 8),
              textoFuerte(context, formatearMoneda(v.total), lineas: 1),
            ]);
          },
          pie: FilaValor('Total del período', formatearMoneda(total), destacado: true),
        ),
      ],
    );
  }
}

class VentaDetalleScreen extends StatefulWidget {
  const VentaDetalleScreen({super.key, required this.numero});

  final int numero;

  @override
  State<VentaDetalleScreen> createState() => _VentaDetalleScreenState();
}

/// Factura de la venta y su recorrido por el pipeline, con el botón para avanzar si al rol le toca.
class _VentaDetalleScreenState extends State<VentaDetalleScreen> with CargaDatos<VentaDetalleScreen, Pedido> {
  bool _avanzando = false;

  PipelineRepository get _pipeline => context.read<PipelineRepository>();

  @override
  Future<Pedido> obtener() => _pipeline.venta(widget.numero);

  Future<void> _avanzar(String destino) async {
    final nota = await pedirNotaAvance(context, widget.numero, destino);
    if (nota == null || !mounted) return;
    setState(() => _avanzando = true);
    try {
      final mensaje = await _pipeline.avanzar(widget.numero, nota: nota.isEmpty ? null : nota);
      if (mounted) avisar(context, mensaje);
      await recargar();
    } on ApiException catch (e) {
      if (mounted) avisar(context, e.message);
    } finally {
      if (mounted) setState(() => _avanzando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = datos;
    final session = context.watch<SessionController>().session;
    final siguiente = p == null ? null : _siguiente(p.estado);
    final puede = siguiente != null && (session?.puedeLlevarA(siguiente) ?? false);
    final compacto = Breakpoints.esCompacto(context);

    final etapas = p == null
        ? null
        : Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(children: [
                  Expanded(child: Text('Etapas de la venta', style: Theme.of(context).textTheme.titleMedium)),
                  PillEtapa(p.estado),
                ]),
                const SizedBox(height: 16),
                LineaTiempoEtapas(estado: p.estado, historial: p.historial),
                if (puede)
                  FilledButton.icon(
                    style: FilledButton.styleFrom(backgroundColor: EstadosVenta.color(siguiente), minimumSize: const Size.fromHeight(44)),
                    onPressed: _avanzando ? null : () => _avanzar(siguiente),
                    icon: Icon(EstadosVenta.icono(siguiente), size: 18),
                    label: Text(EstadosVenta.accion(siguiente)),
                  )
                else if (siguiente != null)
                  textoSecundario(context, 'Siguiente paso: ${EstadosVenta.nombre(siguiente)} · lo hace ${EstadosVenta.responsable(siguiente).toLowerCase()}.'),
              ]),
            ),
          );
    final factura = p == null
        ? null
        : Card(
            child: Padding(padding: EdgeInsets.all(compacto ? 16 : 24), child: FacturaView(pedido: p)),
          );

    return ModuloPage(
      titulo: 'Venta A-${widget.numero}',
      maxWidth: 1240,
      alRefrescar: recargar,
      children: [
        if (cargando || _avanzando) const LinearProgressIndicator(),
        if (error != null) InlineBanner.error(error!, alReintentar: recargar),
        if (p != null)
          LayoutBuilder(builder: (context, c) => c.maxWidth >= 1000
              ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(flex: 3, child: factura!),
                  const SizedBox(width: 16),
                  Expanded(flex: 2, child: etapas!),
                ])
              : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [etapas!, const SizedBox(height: 16), factura!])),
        if (p != null)
          Text('La partida contable de esta venta está en el libro diario (origen "Venta").',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.textSecondary)),
      ],
    );
  }

  static String? _siguiente(String estado) {
    final i = EstadosVenta.orden.indexOf(estado);
    return i < 0 || i == EstadosVenta.orden.length - 1 ? null : EstadosVenta.orden[i + 1];
  }
}
