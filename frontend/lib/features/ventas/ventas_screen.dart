import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/security/permisos.dart';
import '../../core/theme/app_theme.dart';
import '../../core/util/formatters.dart';
import '../../core/widgets/app_shell.dart';
import '../../core/widgets/erp_widgets.dart';
import '../../data/models/erp.dart';
import '../../data/models/pedido.dart';
import '../../data/repositories/pedido_repository.dart';
import '../auth/session_controller.dart';
import '../shell/modulo_page.dart';
import 'factura_view.dart';

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
          filas: lista.length,
          alTocar: (i) => _abrir(lista[i]),
          vacio: const EmptyState(icono: Icons.receipt_long_outlined, titulo: 'No hay ventas en este rango'),
          columnas: [
            const ColumnaTabla('Factura', flex: 2),
            const ColumnaTabla('Fecha', flex: 2),
            const ColumnaTabla('Cliente', flex: 4),
            if (!soloMias) const ColumnaTabla('Vendedor', flex: 3),
            const ColumnaTabla('Pago', flex: 2),
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
              textoSecundario(context, formaPagoLegible(v.formaPago)),
              textoFuerte(context, formatearMoneda(v.total), lineas: 1),
            ];
          },
          ficha: (i) {
            final v = lista[i];
            return Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  textoFuerte(context, 'Factura ${v.serie}-${v.numero} · ${v.clienteNombre}', lineas: 1),
                  textoSecundario(context, '${formatearFecha(v.fecha)} · ${formaPagoLegible(v.formaPago)}'),
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

class _VentaDetalleScreenState extends State<VentaDetalleScreen> with CargaDatos<VentaDetalleScreen, Pedido> {
  @override
  Future<Pedido> obtener() => context.read<PedidoRepository>().obtener(widget.numero);

  @override
  Widget build(BuildContext context) {
    final p = datos;
    return ModuloPage(
      titulo: 'Factura A-${widget.numero}',
      maxWidth: 820,
      children: [
        if (cargando) const LinearProgressIndicator(),
        if (error != null) InlineBanner.error(error!),
        if (p != null)
          Card(
            child: Padding(
              padding: EdgeInsets.all(Breakpoints.esCompacto(context) ? 16 : 24),
              child: FacturaView(pedido: p),
            ),
          ),
        if (p != null)
          Text('La partida contable de esta venta está en el libro diario (origen "Venta").',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.textSecondary)),
      ],
    );
  }
}
