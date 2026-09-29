import 'package:flutter/material.dart';

import '../../core/util/formatters.dart';
import '../../data/models/pedido.dart';

/// Muestra exactamente lo que devolvió la API: número, detalle y total definitivo.
class OrderConfirmationScreen extends StatelessWidget {
  const OrderConfirmationScreen({super.key, required this.pedido});

  final Pedido pedido;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Pedido confirmado'), automaticallyImplyLeading: false),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 700),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Icon(Icons.check_circle, size: 64, color: theme.colorScheme.primary),
              const SizedBox(height: 8),
              Text('Pedido #${pedido.numero}',
                  key: const Key('numero-pedido'),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineMedium),
              Text(formatearFecha(pedido.fecha), textAlign: TextAlign.center),
              const SizedBox(height: 24),
              Card(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    columns: const [
                      DataColumn(label: Text('Producto')),
                      DataColumn(label: Text('Cant.'), numeric: true),
                      DataColumn(label: Text('Precio'), numeric: true),
                      DataColumn(label: Text('Subtotal'), numeric: true),
                    ],
                    rows: [
                      for (final l in pedido.lineas)
                        DataRow(cells: [
                          DataCell(Text('${l.codigo} · ${l.nombre}')),
                          DataCell(Text('${l.cantidad}')),
                          DataCell(Text(formatearMoneda(l.precioUnitario))),
                          DataCell(Text(formatearMoneda(l.subtotal))),
                        ]),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Total', style: theme.textTheme.titleLarge),
                  Text(formatearMoneda(pedido.total),
                      key: const Key('total-pedido'), style: theme.textTheme.headlineSmall),
                ],
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: () => Navigator.of(context).popUntil((r) => r.isFirst),
                child: const Text('Volver al catálogo'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
