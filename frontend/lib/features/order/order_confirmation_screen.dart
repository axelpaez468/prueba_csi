import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_shell.dart';
import '../../data/models/pedido.dart';
import '../shell/app_top_bar.dart';
import '../ventas/factura_view.dart';

/// Comprobante de la venta: muestra exactamente lo que devolvió la API (factura, detalle y total definitivo).
class OrderConfirmationScreen extends StatelessWidget {
  const OrderConfirmationScreen({super.key, required this.pedido});

  final Pedido pedido;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final compacto = Breakpoints.esCompacto(context);

    return Scaffold(
      appBar: const AppTopBar(),
      body: SingleChildScrollView(
        padding: EdgeInsets.symmetric(vertical: compacto ? 16 : 32, horizontal: compacto ? 12 : 24),
        child: PageBody(
          maxWidth: 760,
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
                      Text('¡Venta registrada!', style: theme.textTheme.headlineSmall, textAlign: TextAlign.center),
                      const SizedBox(height: 4),
                      Text('Se emitió la factura y se actualizaron el inventario y la contabilidad.',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary)),
                    ],
                  ),
                ),
                Padding(
                  padding: EdgeInsets.all(compacto ? 16 : 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      FacturaView(pedido: pedido),
                      const SizedBox(height: 24),
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
