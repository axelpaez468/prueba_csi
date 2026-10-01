import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/util/formatters.dart';
import '../../core/widgets/erp_widgets.dart';
import '../../data/models/pipeline.dart';
import '../../data/models/pronostico.dart';

/// Colores del pronóstico: lo cerrado, lo esperado de las abiertas y lo abierto que no se espera cerrar.
class ColoresPronostico {
  const ColoresPronostico._();

  static const cerrado = AppColors.success;
  static const esperado = AppColors.primary;
  static const resto = Color(0xFFD5DEEE);
}

/// Cuadrito de color con su texto, para las leyendas.
class Leyenda extends StatelessWidget {
  const Leyenda(this.color, this.texto, {super.key});

  final Color color;
  final String texto;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 12,
        height: 12,
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3)),
      ),
      const SizedBox(width: 6),
      Flexible(child: textoSecundario(context, texto)),
    ],
  );
}

/// Tres barras en la misma escala: lo cerrado, el pronóstico (cerrado + esperado) y el máximo posible si
/// todo el pipeline se cerrara (cerrado + todo lo abierto).
class GraficaCerradoVsPronostico extends StatelessWidget {
  const GraficaCerradoVsPronostico({super.key, required this.pronostico});

  final Pronostico pronostico;

  @override
  Widget build(BuildContext context) {
    final p = pronostico;
    final maximo = p.cerrado + p.abierto;
    final resto = (p.abierto - p.ponderadoAbierto).clamp(0, double.infinity).toDouble();
    final angosto = MediaQuery.sizeOf(context).width < 600;

    Widget fila(String titulo, String detalle, double total, List<(double, Color)> partes) {
      final barra = ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          height: 26,
          child: LayoutBuilder(
            builder: (context, c) {
              return Stack(
                children: [
                  const Positioned.fill(child: ColoredBox(color: Color(0xFFF1F4F9))),
                  Row(
                    children: [
                      for (final (valor, color) in partes)
                        if (valor > 0 && maximo > 0) Container(width: c.maxWidth * valor / maximo, color: color),
                    ],
                  ),
                ],
              );
            },
          ),
        ),
      );
      final monto = textoFuerte(context, formatearMoneda(total), lineas: 1);
      final etiqueta = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [textoFuerte(context, titulo, lineas: 1), textoSecundario(context, detalle, lineas: 2)],
      );
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: angosto
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(child: etiqueta),
                      const SizedBox(width: 8),
                      monto,
                    ],
                  ),
                  const SizedBox(height: 6),
                  barra,
                ],
              )
            : Row(
                children: [
                  SizedBox(width: 210, child: etiqueta),
                  const SizedBox(width: 12),
                  Expanded(child: barra),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 140,
                    child: Align(alignment: Alignment.centerRight, child: monto),
                  ),
                ],
              ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        fila('Cerrado', '${p.facturasCerradas} ventas entregadas y cobradas', p.cerrado, [
          (p.cerrado, ColoresPronostico.cerrado),
        ]),
        fila('Pronóstico', 'Cerrado + ${formatearMoneda(p.ponderadoAbierto)} esperado de las abiertas', p.pronostico, [
          (p.cerrado, ColoresPronostico.cerrado),
          (p.ponderadoAbierto, ColoresPronostico.esperado),
        ]),
        fila('Si todo se cerrara', 'Cerrado + las ${p.facturasAbiertas} ventas abiertas completas', maximo, [
          (p.cerrado, ColoresPronostico.cerrado),
          (p.ponderadoAbierto, ColoresPronostico.esperado),
          (resto, ColoresPronostico.resto),
        ]),
        const SizedBox(height: 8),
        Wrap(
          spacing: 18,
          runSpacing: 8,
          children: const [
            Leyenda(ColoresPronostico.cerrado, 'Cerrado'),
            Leyenda(ColoresPronostico.esperado, 'Esperado (total de la etapa × probabilidad)'),
            Leyenda(ColoresPronostico.resto, 'Abierto que no se espera cerrar'),
          ],
        ),
      ],
    );
  }
}

/// Embudo del pipeline: una barra centrada por etapa, de ancho proporcional al monto en esa etapa.
class EmbudoPipeline extends StatelessWidget {
  const EmbudoPipeline({super.key, required this.etapas});

  final List<EtapaPronostico> etapas;

  @override
  Widget build(BuildContext context) {
    final maximo = etapas.fold<double>(0, (m, e) => e.total > m ? e.total : m);
    return Column(
      children: [
        for (final e in etapas)
          Tooltip(
            message: '${e.nombre}: ${e.facturas} ventas · ${formatearMoneda(e.total)}',
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  SizedBox(
                    width: 96,
                    child: Row(
                      children: [
                        Icon(EstadosVenta.icono(e.estado), size: 16, color: EstadosVenta.color(e.estado)),
                        const SizedBox(width: 6),
                        Expanded(child: textoSecundario(context, EstadosVenta.nombre(e.estado).split(' /').first, lineas: 1)),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Center(
                      child: FractionallySizedBox(
                        widthFactor: maximo == 0 ? 0.08 : (e.total / maximo).clamp(0.08, 1.0),
                        child: Container(
                          height: 30,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: e.facturas == 0 ? AppColors.border : EstadosVenta.color(e.estado),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: FittedBox(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 6),
                              child: Text(
                                '${e.facturas}',
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 112,
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: FittedBox(fit: BoxFit.scaleDown, child: textoFuerte(context, formatearMoneda(e.total), lineas: 1)),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// Por etapa, dos barras: el total de las ventas (claro) y lo esperado según la probabilidad (sólido).
class GraficaEtapas extends StatelessWidget {
  const GraficaEtapas({super.key, required this.etapas, this.alto = 230});

  final List<EtapaPronostico> etapas;
  final double alto;

  @override
  Widget build(BuildContext context) {
    final maximo = etapas.fold<double>(0, (m, e) => e.total > m ? e.total : m);
    double factor(double v) => maximo == 0 ? 0.01 : (v / maximo).clamp(0.01, 1.0);

    Widget barra(double valor, Color color) => Expanded(
      child: Align(
        alignment: Alignment.bottomCenter,
        child: FractionallySizedBox(
          heightFactor: factor(valor),
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 2),
            decoration: BoxDecoration(
              color: color,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(5)),
            ),
          ),
        ),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: alto,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final e in etapas)
                Expanded(
                  child: Tooltip(
                    message:
                        '${e.nombre}\nTotal ${formatearMoneda(e.total)} × ${formatearPorcentaje(e.probabilidad)}'
                        ' = ${formatearMoneda(e.ponderado)}',
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: EstadosVenta.color(e.estado).withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(99),
                            ),
                            child: FittedBox(
                              child: Text(
                                formatearPorcentaje(e.probabilidad),
                                style: TextStyle(color: EstadosVenta.color(e.estado), fontSize: 12, fontWeight: FontWeight.w700),
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Expanded(
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                barra(e.total, EstadosVenta.color(e.estado).withValues(alpha: 0.28)),
                                barra(e.ponderado, EstadosVenta.color(e.estado)),
                              ],
                            ),
                          ),
                          const SizedBox(height: 8),
                          SizedBox(
                            height: 16,
                            child: FittedBox(child: textoSecundario(context, EstadosVenta.nombre(e.estado).split(' /').first)),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 18,
          runSpacing: 8,
          children: [
            Leyenda(AppColors.textSecondary.withValues(alpha: 0.3), 'Total de la etapa'),
            const Leyenda(AppColors.textSecondary, 'Esperado = total × probabilidad'),
          ],
        ),
      ],
    );
  }
}

/// Tendencia por día, semana o mes: cerrado y esperado apilados, sobre el total abierto (fondo claro).
class GraficaTendencia extends StatelessWidget {
  const GraficaTendencia({super.key, required this.tramos, required this.agrupacion, this.alto = 220});

  final List<TramoPronostico> tramos;
  final String agrupacion;
  final double alto;

  String _etiqueta(TramoPronostico t) => switch (agrupacion) {
    'MES' => '${mesCorto(t.desde)} ${t.desde.year % 100}',
    'SEMANA' => '${t.desde.day}/${t.desde.month}',
    _ => tramos.length <= 7 ? diaCorto(t.desde) : '${t.desde.day}',
  };

  String _periodo(TramoPronostico t) => switch (agrupacion) {
    'MES' => '${mesCorto(t.desde)} ${t.desde.year}',
    'SEMANA' => 'Semana del ${formatearDia(t.desde)} al ${formatearDia(t.hasta)}',
    _ => formatearDia(t.desde),
  };

  @override
  Widget build(BuildContext context) {
    final maximo = tramos.fold<double>(0, (m, t) => t.cerrado + t.abierto > m ? t.cerrado + t.abierto : m);
    final paso = (tramos.length / 10).ceil().clamp(1, 1000);
    final separacion = tramos.length > 20 ? 1.5 : 5.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: alto,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final (i, t) in tramos.indexed)
                Expanded(
                  child: Tooltip(
                    message:
                        '${_periodo(t)}\nCerrado ${formatearMoneda(t.cerrado)}\n'
                        'Esperado ${formatearMoneda(t.ponderado)} de ${formatearMoneda(t.abierto)} abierto\n'
                        'Pronóstico ${formatearMoneda(t.cerrado + t.ponderado)}',
                    child: Column(
                      children: [
                        Expanded(
                          child: LayoutBuilder(
                            builder: (context, c) {
                              double h(double v) => maximo == 0 ? 0 : c.maxHeight * v / maximo;
                              return Padding(
                                padding: EdgeInsets.symmetric(horizontal: separacion),
                                child: Stack(
                                  alignment: Alignment.bottomCenter,
                                  children: [
                                    // Fondo: todo lo vendido en el tramo (cerrado + abierto).
                                    Container(
                                      height: h(t.cerrado + t.abierto).clamp(2, c.maxHeight),
                                      decoration: const BoxDecoration(
                                        color: ColoresPronostico.resto,
                                        borderRadius: BorderRadius.vertical(top: Radius.circular(4)),
                                      ),
                                    ),
                                    Column(
                                      mainAxisAlignment: MainAxisAlignment.end,
                                      children: [
                                        Container(height: h(t.ponderado), color: ColoresPronostico.esperado),
                                        Container(height: h(t.cerrado), color: ColoresPronostico.cerrado),
                                      ],
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          height: 16,
                          child: i % paso == 0
                              ? OverflowBox(maxWidth: 80, child: FittedBox(child: textoSecundario(context, _etiqueta(t))))
                              : null,
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 18,
          runSpacing: 8,
          children: const [
            Leyenda(ColoresPronostico.cerrado, 'Cerrado'),
            Leyenda(ColoresPronostico.esperado, 'Esperado de las abiertas'),
            Leyenda(ColoresPronostico.resto, 'Resto de lo abierto'),
          ],
        ),
      ],
    );
  }
}
