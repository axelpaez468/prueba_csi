import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/util/formatters.dart';
import '../../core/widgets/erp_widgets.dart';
import '../../data/models/pipeline.dart';

/// Etiqueta de la etapa de la venta, con su color.
class PillEtapa extends StatelessWidget {
  const PillEtapa(this.estado, {super.key});

  final String estado;

  @override
  Widget build(BuildContext context) {
    final color = EstadosVenta.color(estado);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(99)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(EstadosVenta.icono(estado), size: 14, color: color),
        const SizedBox(width: 4),
        Flexible(
          child: Text(EstadosVenta.nombre(estado),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
        ),
      ]),
    );
  }
}

/// Recorrido de la venta por las etapas: hechas (con fecha y quién), la actual y las que faltan.
class LineaTiempoEtapas extends StatelessWidget {
  const LineaTiempoEtapas({super.key, required this.estado, required this.historial});

  final String estado;
  final List<HistorialEstado> historial;

  @override
  Widget build(BuildContext context) {
    final actual = EstadosVenta.orden.indexOf(estado);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (i, etapa) in EstadosVenta.orden.indexed)
          _Paso(
            etapa: etapa,
            hecho: i <= actual,
            esActual: i == actual,
            ultimo: i == EstadosVenta.orden.length - 1,
            registro: historial.where((h) => h.estado == etapa).lastOrNull,
          ),
      ],
    );
  }
}

class _Paso extends StatelessWidget {
  const _Paso({required this.etapa, required this.hecho, required this.esActual, required this.ultimo, this.registro});

  final String etapa;
  final bool hecho;
  final bool esActual;
  final bool ultimo;
  final HistorialEstado? registro;

  @override
  Widget build(BuildContext context) {
    final color = hecho ? EstadosVenta.color(etapa) : AppColors.border;
    final theme = Theme.of(context);
    return IntrinsicHeight(
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SizedBox(
          width: 36,
          child: Column(children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: hecho ? color : Colors.white,
                shape: BoxShape.circle,
                border: Border.all(color: color, width: 2),
                boxShadow: esActual ? [BoxShadow(color: color.withValues(alpha: 0.35), blurRadius: 10)] : null,
              ),
              child: Icon(EstadosVenta.icono(etapa), size: 16, color: hecho ? Colors.white : AppColors.textSecondary),
            ),
            if (!ultimo) Expanded(child: Container(width: 2, color: hecho ? color : AppColors.border)),
          ]),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 18),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(EstadosVenta.nombre(etapa),
                  style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: esActual ? FontWeight.w700 : FontWeight.w500,
                      color: hecho ? AppColors.textPrimary : AppColors.textSecondary)),
              if (registro != null)
                textoSecundario(context,
                    [formatearFecha(registro!.fecha), ?registro!.usuario, ?registro!.nota].join(' · '))
              else if (!hecho && EstadosVenta.responsable(etapa).isNotEmpty)
                textoSecundario(context, 'Pendiente · lo hace ${EstadosVenta.responsable(etapa).toLowerCase()}'),
            ]),
          ),
        ),
      ]),
    );
  }
}

/// Pide una nota opcional y confirma el paso a la siguiente etapa. Devuelve la nota, '' sin nota, o null si se canceló.
Future<String?> pedirNotaAvance(BuildContext context, int numero, String destino) =>
    showDialog<String>(context: context, builder: (_) => _DialogoNota(numero: numero, destino: destino));

/// El controlador vive en el estado del diálogo para liberarlo cuando termina la animación de cierre.
class _DialogoNota extends StatefulWidget {
  const _DialogoNota({required this.numero, required this.destino});

  final int numero;
  final String destino;

  @override
  State<_DialogoNota> createState() => _DialogoNotaState();
}

class _DialogoNotaState extends State<_DialogoNota> {
  final _nota = TextEditingController();

  @override
  void dispose() {
    _nota.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('${EstadosVenta.accion(widget.destino)} · A-${widget.numero}'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('La venta pasará a "${EstadosVenta.nombre(widget.destino)}".'),
          const SizedBox(height: 12),
          TextField(
            controller: _nota,
            autofocus: true,
            maxLength: 200,
            decoration: const InputDecoration(labelText: 'Nota (opcional)', hintText: 'Guía 4521, entregado a recepción...'),
            onSubmitted: (v) => Navigator.of(context).pop(v.trim()),
          ),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancelar')),
        FilledButton(onPressed: () => Navigator.of(context).pop(_nota.text.trim()), child: Text(EstadosVenta.accion(widget.destino))),
      ],
    );
  }
}
