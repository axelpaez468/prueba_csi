import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/util/formatters.dart';
import '../../core/widgets/erp_widgets.dart';
import '../../data/models/erp.dart';
import '../../data/models/pedido.dart';

/// Factura de la venta (simulación de FEL): emisor, receptor, detalle y totales con el IVA desglosado.
class FacturaView extends StatelessWidget {
  const FacturaView({super.key, required this.pedido});

  final Pedido pedido;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final secundario = theme.textTheme.bodySmall?.copyWith(color: AppColors.textSecondary);

    Widget dato(String etiqueta, String valor, {Key? key, CrossAxisAlignment alinear = CrossAxisAlignment.start}) => Column(
          crossAxisAlignment: alinear,
          children: [
            Text(etiqueta.toUpperCase(), style: secundario),
            const SizedBox(height: 2),
            Text(valor, key: key, style: theme.textTheme.titleSmall),
          ],
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          spacing: 24,
          runSpacing: 12,
          children: [
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('FACTURA', style: secundario),
              Text('Serie ${pedido.serie} · No. ${pedido.numero}',
                  key: const Key('numero-pedido'), style: theme.textTheme.titleLarge),
            ]),
            dato('Fecha de emisión', formatearFecha(pedido.fecha), alinear: CrossAxisAlignment.end),
          ],
        ),
        if (pedido.autorizacion != null) ...[
          const SizedBox(height: 8),
          SelectableText('Autorización: ${pedido.autorizacion!.toUpperCase()}', style: secundario),
        ],
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(10)),
          child: Wrap(
            spacing: 32,
            runSpacing: 12,
            children: [
              dato('NIT', pedido.clienteNit),
              dato('Cliente', pedido.clienteNombre),
              if (pedido.clienteDireccion != null) dato('Dirección', pedido.clienteDireccion!),
              dato('Forma de pago', '${formaPagoLegible(pedido.formaPago)} (contado)'),
              if (pedido.vendedor != null) dato('Vendedor', pedido.vendedor!),
            ],
          ),
        ),
        const SizedBox(height: 20),
        LayoutBuilder(builder: (context, constraints) {
          // En celular no caben 4 columnas: cantidad y precio van bajo el nombre.
          final tabla = constraints.maxWidth >= 480;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (tabla) ...[
                _FilaDetalle(
                  producto: Text('Descripción', style: secundario),
                  cantidad: Text('Cant.', style: secundario, textAlign: TextAlign.center),
                  precio: Text('Precio', style: secundario, textAlign: TextAlign.end),
                  subtotal: Text('Subtotal', style: secundario, textAlign: TextAlign.end),
                ),
                const Divider(),
              ],
              for (final l in pedido.lineas) ...[
                if (tabla)
                  _FilaDetalle(
                    producto: _NombreLinea(linea: l, estilo: secundario),
                    cantidad: Text('${l.cantidad}', textAlign: TextAlign.center),
                    precio: Text(formatearMoneda(l.precioUnitario), textAlign: TextAlign.end),
                    subtotal: Text(formatearMoneda(l.subtotal),
                        textAlign: TextAlign.end, style: const TextStyle(fontWeight: FontWeight.w600)),
                  )
                else
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _NombreLinea(linea: l, estilo: secundario),
                              const SizedBox(height: 2),
                              Text('${l.cantidad} × ${formatearMoneda(l.precioUnitario)}', style: secundario),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(formatearMoneda(l.subtotal), style: const TextStyle(fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                const Divider(),
              ],
            ],
          );
        }),
        const SizedBox(height: 8),
        FilaValor('Base imponible (sin IVA)', formatearMoneda(pedido.baseImponible)),
        FilaValor('IVA 12 %', formatearMoneda(pedido.iva)),
        const SizedBox(height: 4),
        Row(
          children: [
            Expanded(child: Text('Total', style: theme.textTheme.titleLarge)),
            Text(formatearMoneda(pedido.total),
                key: const Key('total-pedido'), style: theme.textTheme.headlineSmall?.copyWith(color: AppColors.primary)),
          ],
        ),
        const SizedBox(height: 12),
        Text('Documento de demostración (simulación de FEL): no tiene validez fiscal.',
            style: secundario, textAlign: TextAlign.center),
      ],
    );
  }
}

class _FilaDetalle extends StatelessWidget {
  const _FilaDetalle({required this.producto, required this.cantidad, required this.precio, required this.subtotal});

  final Widget producto;
  final Widget cantidad;
  final Widget precio;
  final Widget subtotal;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Expanded(child: producto),
          SizedBox(width: 60, child: cantidad),
          SizedBox(width: 110, child: precio),
          SizedBox(width: 120, child: subtotal),
        ],
      ),
    );
  }
}

class _NombreLinea extends StatelessWidget {
  const _NombreLinea({required this.linea, required this.estilo});

  final PedidoLinea linea;
  final TextStyle? estilo;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(linea.nombre, style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
          Text(linea.codigo, style: estilo),
        ],
      );
}
