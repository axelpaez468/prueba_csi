import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Logotipo de la aplicación (ícono + nombre).
class BrandLogo extends StatelessWidget {
  const BrandLogo({super.key, this.claro = false, this.soloIcono = false});

  /// true sobre fondos oscuros.
  final bool claro;

  /// true en pantallas muy angostas: se omite el nombre.
  final bool soloIcono;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: claro ? Colors.white.withValues(alpha: 0.15) : AppColors.primary,
            borderRadius: BorderRadius.circular(9),
          ),
          child: const Icon(Icons.inventory_2_outlined, color: Colors.white, size: 19),
        ),
        if (!soloIcono) ...[
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              'Pedidos',
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: claro ? Colors.white : AppColors.textPrimary,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.3,
                  ),
            ),
          ),
        ],
      ],
    );
  }
}

/// Puntos de quiebre de la interfaz.
class Breakpoints {
  const Breakpoints._();

  /// Por debajo de este ancho se usa el diseño de celular.
  static const compacto = 600.0;

  /// Desde este ancho se usan diseños de dos columnas (login, carrito).
  static const amplio = 900.0;

  static bool esCompacto(BuildContext context) => MediaQuery.sizeOf(context).width < compacto;
}

/// Contenedor centrado que ocupa todo el ancho disponible hasta [maxWidth].
class PageBody extends StatelessWidget {
  const PageBody({super.key, required this.child, this.maxWidth = 1180});

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: SizedBox(width: double.infinity, child: child),
      ),
    );
  }
}

/// Encabezado de página: título, subtítulo y acciones opcionales a la derecha.
class PageHeader extends StatelessWidget {
  const PageHeader({super.key, required this.titulo, this.subtitulo, this.acciones = const []});

  final String titulo;
  final String? subtitulo;
  final List<Widget> acciones;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textos = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(titulo, style: theme.textTheme.headlineSmall),
        if (subtitulo != null) ...[
          const SizedBox(height: 4),
          Text(subtitulo!, style: theme.textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary)),
        ],
      ],
    );
    final botonesAmplio = Wrap(spacing: 8, runSpacing: 8, children: acciones);
    // En pantallas angostas la primera acción (p. ej. el buscador) ocupa todo el espacio sobrante.
    final botonesAngosto = Row(
      children: [
        for (final (i, a) in acciones.indexed) ...[
          if (i > 0) const SizedBox(width: 8),
          i == 0 ? Expanded(child: a) : a,
        ],
      ],
    );

    final margen = Breakpoints.esCompacto(context) ? 16.0 : 24.0;

    return Padding(
      padding: EdgeInsets.fromLTRB(margen, margen + 4, margen, 20),
      child: LayoutBuilder(
        builder: (context, constraints) => acciones.isEmpty
            ? Align(alignment: Alignment.centerLeft, child: textos)
            : constraints.maxWidth >= 760
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [Expanded(child: textos), botonesAmplio],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [textos, const SizedBox(height: 16), botonesAngosto],
                  ),
      ),
    );
  }
}

/// Etiqueta de estado con color (stock, rol, etc.).
class StatusPill extends StatelessWidget {
  const StatusPill({super.key, required this.texto, required this.color, required this.fondo, this.icono});

  final String texto;
  final Color color;
  final Color fondo;
  final IconData? icono;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: fondo, borderRadius: BorderRadius.circular(999)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icono != null) ...[Icon(icono, size: 14, color: color), const SizedBox(width: 4)],
          Text(texto, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

/// Aviso de error o información dentro de una página.
class InlineBanner extends StatelessWidget {
  const InlineBanner.error(this.mensaje, {super.key})
      : color = AppColors.danger,
        fondo = AppColors.dangerBg,
        icono = Icons.error_outline;

  const InlineBanner.info(this.mensaje, {super.key})
      : color = AppColors.warning,
        fondo = AppColors.warningBg,
        icono = Icons.info_outline;

  final String mensaje;
  final Color color;
  final Color fondo;
  final IconData icono;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: fondo,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icono, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(child: Text(mensaje, style: TextStyle(color: color, fontWeight: FontWeight.w500))),
        ],
      ),
    );
  }
}

/// Estado vacío con ícono, mensaje y acción opcional.
class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icono, required this.titulo, this.mensaje, this.accion});

  final IconData icono;
  final String titulo;
  final String? mensaje;
  final Widget? accion;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: const BoxDecoration(color: Color(0xFFE8EDF4), shape: BoxShape.circle),
              child: Icon(icono, size: 34, color: AppColors.primary),
            ),
            const SizedBox(height: 16),
            Text(titulo, style: theme.textTheme.titleMedium, textAlign: TextAlign.center),
            if (mensaje != null) ...[
              const SizedBox(height: 6),
              Text(mensaje!,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary)),
            ],
            if (accion != null) ...[const SizedBox(height: 20), accion!],
          ],
        ),
      ),
    );
  }
}
