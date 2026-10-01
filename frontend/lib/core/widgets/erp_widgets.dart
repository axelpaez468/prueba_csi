import 'package:flutter/material.dart';

import '../network/api_exception.dart';
import '../theme/app_theme.dart';
import '../util/formatters.dart';
import 'app_shell.dart';

/// Carga de datos de una pantalla: estado de carga, error y recarga (pull-to-refresh o botón).
mixin CargaDatos<W extends StatefulWidget, T> on State<W> {
  T? datos;
  bool cargando = true;
  String? error;

  Future<T> obtener();

  @override
  void initState() {
    super.initState();
    _ejecutar();
  }

  Future<void> recargar() async {
    setState(() {
      cargando = true;
      error = null;
    });
    await _ejecutar();
  }

  Future<void> _ejecutar() async {
    try {
      final r = await obtener();
      if (mounted) setState(() => datos = r);
    } on UnauthorizedException {
      // La app vuelve al login.
    } on ApiException catch (e) {
      if (mounted) setState(() => error = e.message);
    } finally {
      if (mounted) setState(() => cargando = false);
    }
  }
}

void avisar(BuildContext context, String mensaje) => ScaffoldMessenger.of(context)
  ..hideCurrentSnackBar()
  ..showSnackBar(SnackBar(content: Text(mensaje)));

Future<bool> confirmar(BuildContext context, String titulo, String mensaje, String accion, {bool peligrosa = false}) async =>
    await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(titulo),
        content: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 420), child: Text(mensaje)),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancelar')),
          FilledButton(
            style: peligrosa ? FilledButton.styleFrom(backgroundColor: AppColors.danger) : null,
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(accion),
          ),
        ],
      ),
    ) ??
    false;

TextStyle? estiloEncabezadoTabla(BuildContext context) =>
    Theme.of(context).textTheme.labelMedium?.copyWith(color: AppColors.textSecondary, letterSpacing: 0.4);

class ColumnaTabla {
  const ColumnaTabla(this.titulo, {this.flex = 2, this.derecha = false});

  final String titulo;
  final int flex;

  /// Montos y cantidades se alinean a la derecha.
  final bool derecha;
}

/// Tabla dentro de una tarjeta que, cuando no cabe, se convierte en una lista de fichas apiladas.
class TablaResponsiva extends StatelessWidget {
  const TablaResponsiva({
    super.key,
    required this.columnas,
    required this.filas,
    required this.celdas,
    required this.ficha,
    this.alTocar,
    this.anchoTabla = 760,
    this.vacio,
    this.cargando = false,
    this.error,
    this.pie,
  });

  final List<ColumnaTabla> columnas;
  final int filas;
  final List<Widget> Function(int i) celdas;

  /// Versión apilada de la fila i (celular).
  final Widget Function(int i) ficha;
  final void Function(int i)? alTocar;
  final double anchoTabla;
  final Widget? vacio;
  final bool cargando;
  final String? error;

  /// Fila de totales (se muestra en ambos modos).
  final Widget? pie;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: LayoutBuilder(builder: (context, constraints) {
        final tabla = constraints.maxWidth >= anchoTabla;
        final encabezado = estiloEncabezadoTabla(context);

        Widget fila(int i) {
          final contenido = tabla
              ? Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  child: Row(children: [
                    for (final (j, c) in celdas(i).indexed)
                      Expanded(
                        flex: columnas[j].flex,
                        child: Padding(
                          // Separación entre columnas: una alineada a la derecha no queda pegada a la siguiente.
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          child: Align(alignment: columnas[j].derecha ? Alignment.centerRight : Alignment.centerLeft, child: c),
                        ),
                      ),
                  ]),
                )
              : Padding(padding: const EdgeInsets.fromLTRB(16, 12, 16, 12), child: ficha(i));
          return alTocar == null ? contenido : InkWell(onTap: () => alTocar!(i), child: contenido);
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (cargando) const LinearProgressIndicator(),
            if (error != null) Padding(padding: const EdgeInsets.all(16), child: InlineBanner.error(error!)),
            if (!cargando && error == null && filas == 0)
              vacio ?? const EmptyState(icono: Icons.inbox_outlined, titulo: 'No hay registros que mostrar'),
            if (tabla && filas > 0) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 12),
                child: Row(children: [
                  for (final c in columnas)
                    Expanded(
                      flex: c.flex,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        child: Text(c.titulo.toUpperCase(),
                            style: encabezado, textAlign: c.derecha ? TextAlign.end : TextAlign.start),
                      ),
                    ),
                ]),
              ),
              const Divider(),
            ],
            for (var i = 0; i < filas; i++) ...[
              if (i > 0) const Divider(),
              fila(i),
            ],
            if (pie != null && filas > 0) ...[
              const Divider(thickness: 1.5),
              Padding(padding: EdgeInsets.symmetric(horizontal: tabla ? 20 : 16, vertical: 14), child: pie!),
            ],
          ],
        );
      }),
    );
  }
}

/// Indicador del panel: título, valor grande y detalle opcional.
class KpiCard extends StatelessWidget {
  const KpiCard({super.key, required this.titulo, required this.valor, required this.icono, this.detalle, this.color});

  final String titulo;
  final String valor;
  final IconData icono;
  final String? detalle;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = color ?? AppColors.primary;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(color: c.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
              child: Icon(icono, color: c, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(titulo, style: theme.textTheme.bodySmall?.copyWith(color: AppColors.textSecondary)),
                  const SizedBox(height: 4),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(valor, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                  ),
                  if (detalle != null) ...[
                    const SizedBox(height: 2),
                    Text(detalle!, style: theme.textTheme.bodySmall?.copyWith(color: AppColors.textSecondary)),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Rejilla que acomoda tarjetas en 1 a 4 columnas según el ancho.
class RejillaAdaptable extends StatelessWidget {
  const RejillaAdaptable({super.key, required this.children, this.anchoMinimo = 240, this.espacio = 16});

  final List<Widget> children;
  final double anchoMinimo;
  final double espacio;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final columnas = (constraints.maxWidth / anchoMinimo).floor().clamp(1, 4);
      final ancho = (constraints.maxWidth - espacio * (columnas - 1)) / columnas;
      return Wrap(
        spacing: espacio,
        runSpacing: espacio,
        children: [for (final c in children) SizedBox(width: ancho, child: c)],
      );
    });
  }
}

/// Botón que muestra y cambia un rango de fechas.
class SelectorRango extends StatelessWidget {
  const SelectorRango({super.key, required this.desde, required this.hasta, required this.alCambiar});

  final DateTime desde;
  final DateTime hasta;
  final void Function(DateTime desde, DateTime hasta) alCambiar;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: () async {
        final rango = await showDateRangePicker(
          context: context,
          firstDate: DateTime(2020),
          lastDate: hoy(),
          initialDateRange: DateTimeRange(start: desde, end: hasta),
          helpText: 'Selecciona el rango',
          saveText: 'Aplicar',
        );
        if (rango != null) alCambiar(rango.start, rango.end);
      },
      icon: const Icon(Icons.date_range, size: 18),
      label: Text('${formatearDia(desde)} – ${formatearDia(hasta)}'),
    );
  }
}

/// Botón para elegir una sola fecha.
class SelectorFecha extends StatelessWidget {
  const SelectorFecha({super.key, required this.fecha, required this.alCambiar, this.etiqueta = 'Al'});

  final DateTime fecha;
  final ValueChanged<DateTime> alCambiar;
  final String etiqueta;

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
        onPressed: () async {
          final f = await showDatePicker(context: context, firstDate: DateTime(2020), lastDate: hoy(), initialDate: fecha);
          if (f != null) alCambiar(f);
        },
        icon: const Icon(Icons.event, size: 18),
        label: Text('$etiqueta ${formatearDia(fecha)}'),
      );
}

/// Fila "etiqueta ....... valor" para resúmenes y totales.
class FilaValor extends StatelessWidget {
  const FilaValor(this.etiqueta, this.valor, {super.key, this.destacado = false, this.color});

  final String etiqueta;
  final String valor;
  final bool destacado;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final estilo = destacado
        ? theme.textTheme.titleMedium?.copyWith(color: color)
        : theme.textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: LayoutBuilder(
        builder: (context, c) => Row(children: [
          Expanded(child: Text(etiqueta, style: estilo)),
          const SizedBox(width: 8),
          // El monto usa su ancho natural; solo si no cabe (celular) se reduce en vez de desbordar.
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: c.maxWidth * 0.6),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Text(valor,
                  style: destacado
                      ? theme.textTheme.titleMedium?.copyWith(color: color ?? AppColors.primary, fontWeight: FontWeight.w700)
                      : theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600, color: color)),
            ),
          ),
        ]),
      ),
    );
  }
}

/// Texto secundario pequeño.
Widget textoSecundario(BuildContext context, String texto, {int? lineas}) => Text(texto,
    maxLines: lineas,
    overflow: lineas == null ? null : TextOverflow.ellipsis,
    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.textSecondary));

/// Texto principal en negrita (nombre de la fila).
Widget textoFuerte(BuildContext context, String texto, {int lineas = 2}) => Text(texto,
    maxLines: lineas,
    overflow: TextOverflow.ellipsis,
    style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600));

class Pills {
  const Pills._();

  static Widget activo(bool activo) => activo
      ? const StatusPill(texto: 'Activo', color: AppColors.success, fondo: AppColors.successBg)
      : const StatusPill(texto: 'Inactivo', color: AppColors.danger, fondo: AppColors.dangerBg);

  static Widget estadoOrden(String estado) => switch (estado) {
        'PENDIENTE' => const StatusPill(texto: 'Pendiente', color: AppColors.warning, fondo: AppColors.warningBg),
        'RECIBIDA' => const StatusPill(texto: 'Recibida', color: AppColors.success, fondo: AppColors.successBg),
        _ => const StatusPill(texto: 'Anulada', color: AppColors.textSecondary, fondo: AppColors.background),
      };

  static Widget origen(String origen) => StatusPill(
        texto: switch (origen) {
          'VENTA' => 'Venta',
          'COMPRA' => 'Compra',
          'AJUSTE' => 'Ajuste',
          'APERTURA' => 'Apertura',
          _ => 'Manual',
        },
        color: origen == 'MANUAL' ? AppColors.primary : AppColors.textSecondary,
        fondo: origen == 'MANUAL' ? const Color(0xFFE3EAFB) : AppColors.background,
      );
}

/// Gráfica de barras simple. Con muchas barras solo se rotulan algunas para que las etiquetas no se encimen.
class GraficaBarras extends StatelessWidget {
  const GraficaBarras({super.key, required this.barras, this.alto = 180});

  /// (etiqueta, valor, texto del tooltip).
  final List<(String, double, String)> barras;
  final double alto;

  @override
  Widget build(BuildContext context) {
    final maximo = barras.fold<double>(0, (m, b) => b.$2 > m ? b.$2 : m);
    final paso = (barras.length / 8).ceil().clamp(1, 1000);
    final separacion = barras.length > 15 ? 2.0 : 6.0;

    return SizedBox(
      height: alto,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final (i, (etiqueta, valor, tooltip)) in barras.indexed)
            Expanded(
              child: Tooltip(
                message: tooltip,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Align(
                        alignment: Alignment.bottomCenter,
                        child: FractionallySizedBox(
                          heightFactor: maximo == 0 ? 0.02 : (valor / maximo).clamp(0.02, 1.0),
                          child: Container(
                            margin: EdgeInsets.symmetric(horizontal: separacion),
                            decoration: BoxDecoration(
                              color: valor > 0 ? AppColors.primary : AppColors.border,
                              borderRadius: const BorderRadius.vertical(top: Radius.circular(5)),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 16,
                      child: i % paso == 0
                          ? OverflowBox(maxWidth: 80, child: FittedBox(child: textoSecundario(context, etiqueta)))
                          : null,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Barra horizontal de participación (porcentaje del total).
class BarraParticipacion extends StatelessWidget {
  const BarraParticipacion({super.key, required this.porcentaje, this.color = AppColors.accent});

  final double porcentaje;
  final Color color;

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(99),
        child: LinearProgressIndicator(
          value: (porcentaje / 100).clamp(0.0, 1.0),
          minHeight: 6,
          backgroundColor: AppColors.background,
          color: color,
        ),
      );
}
