import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/util/formatters.dart';
import '../../core/widgets/app_shell.dart';
import '../../data/models/pedido.dart';
import '../shell/app_top_bar.dart';

/// Comprobante del pedido: muestra exactamente lo que devolvió la API (número, detalle y total definitivo).
class OrderConfirmationScreen extends StatelessWidget {
  const OrderConfirmationScreen({super.key, required this.pedido});

  final Pedido pedido;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final secundario = theme.textTheme.bodySmall?.copyWith(color: AppColors.textSecondary);

    return Scaffold(
      appBar: const AppTopBar(),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
        child: PageBody(
          maxWidth: 720,
          child: Card(
            clipBehavior: Clip.antiAlias,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  color: AppColors.successBg,
                  padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 24),
                  child: Column(
                    children: [
                      Container(
                        width: 56,
                        height: 56,
                        decoration: const BoxDecoration(color: AppColors.success, shape: BoxShape.circle),
                        child: const Icon(Icons.check, color: Colors.white, size: 32),
                      ),
                      const SizedBox(height: 14),
                      Text('¡Pedido confirmado!', style: theme.textTheme.headlineSmall),
                      const SizedBox(height: 4),
                      Text('El inventario ya fue actualizado.',
                          style: theme.textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary)),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Wrap(
                        alignment: WrapAlignment.spaceBetween,
                        runSpacing: 12,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('NÚMERO DE PEDIDO', style: secundario),
                              Text('#${pedido.numero}',
                                  key: const Key('numero-pedido'), style: theme.textTheme.titleLarge),
                            ],
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text('FECHA', style: secundario),
                              Text(formatearFecha(pedido.fecha), style: theme.textTheme.titleMedium),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      _FilaDetalle(
                        producto: Text('Producto', style: secundario),
                        cantidad: Text('Cant.', style: secundario, textAlign: TextAlign.center),
                        precio: Text('Precio', style: secundario, textAlign: TextAlign.end),
                        subtotal: Text('Subtotal', style: secundario, textAlign: TextAlign.end),
                      ),
                      const Divider(),
                      for (final l in pedido.lineas) ...[
                        _FilaDetalle(
                          producto: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(l.nombre, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                              Text(l.codigo, style: secundario),
                            ],
                          ),
                          cantidad: Text('${l.cantidad}', textAlign: TextAlign.center),
                          precio: Text(formatearMoneda(l.precioUnitario), textAlign: TextAlign.end),
                          subtotal: Text(formatearMoneda(l.subtotal),
                              textAlign: TextAlign.end, style: const TextStyle(fontWeight: FontWeight.w600)),
                        ),
                        const Divider(),
                      ],
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(child: Text('Total', style: theme.textTheme.titleLarge)),
                          Text(formatearMoneda(pedido.total),
                              key: const Key('total-pedido'),
                              style: theme.textTheme.headlineSmall?.copyWith(color: AppColors.primary)),
                        ],
                      ),
                      const SizedBox(height: 28),
                      FilledButton.icon(
                        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                        onPressed: () => Navigator.of(context).popUntil((r) => r.isFirst),
                        icon: const Icon(Icons.storefront_outlined, size: 18),
                        label: const Text('Volver al catálogo'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
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
