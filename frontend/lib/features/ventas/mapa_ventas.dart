import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/app_theme.dart';
import '../../core/util/formatters.dart';
import '../../core/widgets/app_shell.dart';
import '../../core/widgets/erp_widgets.dart';
import '../../data/models/erp.dart';

/// Contorno de un departamento (longitud, latitud).
class _Forma {
  const _Forma(this.nombre, this.iso, this.anillos);

  final String nombre;
  final String iso;
  final List<List<Offset>> anillos;
}

/// Límites de los 22 departamentos (geoBoundaries / OpenStreetMap, ODbL). Se leen una sola vez.
Future<List<_Forma>>? _formas;

/// Formas ya leídas: si están, el mapa se dibuja sin esperar.
List<_Forma>? _formasCargadas;

Future<List<_Forma>> _cargarFormas() => _formas ??= () async {
      // load + utf8 en lugar de loadString: con archivos grandes, loadString decodifica en otro isolate.
      final bytes = await rootBundle.load('assets/mapas/guatemala-departamentos.geojson');
      final json = jsonDecode(utf8.decode(bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes)))
          as Map<String, dynamic>;
      List<Offset> anillo(List<dynamic> puntos) =>
          [for (final p in puntos) Offset((p[0] as num).toDouble(), (p[1] as num).toDouble())];
      return _formasCargadas = [
        for (final f in (json['features'] as List).cast<Map<String, dynamic>>())
          _Forma(
            f['properties']['nombre'] as String,
            f['properties']['iso'] as String,
            switch (f['geometry']['type']) {
              'MultiPolygon' => [
                  for (final poligono in f['geometry']['coordinates'] as List)
                    for (final a in poligono as List) anillo(a as List),
                ],
              _ => [for (final a in f['geometry']['coordinates'] as List) anillo(a as List)],
            },
          ),
      ];
    }();

/// Carga el contorno de los departamentos por adelantado (lo usan las pruebas, que no esperan E/S real).
Future<void> precargarMapa() => _cargarFormas();

/// Proyección simple (equirectangular corregida por la latitud): suficiente para un país del tamaño de Guatemala.
class _Proyeccion {
  _Proyeccion(List<_Forma> formas, Size tamano) {
    var minX = double.infinity, maxX = -double.infinity, minY = double.infinity, maxY = -double.infinity;
    for (final f in formas) {
      for (final a in f.anillos) {
        for (final p in a) {
          minX = math.min(minX, p.dx);
          maxX = math.max(maxX, p.dx);
          minY = math.min(minY, p.dy);
          maxY = math.max(maxY, p.dy);
        }
      }
    }
    _minX = minX;
    _maxY = maxY;
    _kx = math.cos((minY + maxY) / 2 * math.pi / 180);
    final ancho = (maxX - minX) * _kx, alto = maxY - minY;
    _escala = math.min(tamano.width / ancho, tamano.height / alto);
    _dx = (tamano.width - ancho * _escala) / 2;
    _dy = (tamano.height - alto * _escala) / 2;
  }

  late final double _minX, _maxY, _kx, _escala, _dx, _dy;

  Offset punto(Offset lonLat) => Offset(_dx + (lonLat.dx - _minX) * _kx * _escala, _dy + (_maxY - lonLat.dy) * _escala);

  Path camino(_Forma f) {
    final path = Path()..fillType = PathFillType.evenOdd;
    for (final a in f.anillos) {
      if (a.isEmpty) continue;
      path.moveTo(punto(a.first).dx, punto(a.first).dy);
      for (final p in a.skip(1)) {
        final q = punto(p);
        path.lineTo(q.dx, q.dy);
      }
      path.close();
    }
    return path;
  }
}

/// Mapa de calor de las ventas por departamento, con el detalle del departamento elegido.
class MapaVentas extends StatefulWidget {
  const MapaVentas({super.key, required this.datos});

  final List<VentaDepartamento> datos;

  @override
  State<MapaVentas> createState() => _MapaVentasState();
}

class _MapaVentasState extends State<MapaVentas> {
  List<_Forma>? _listas = _formasCargadas;
  bool _fallo = false;
  String? _hover;
  String? _elegido;

  static const _sinVentas = Color(0xFFF1F4F9);
  static const _claro = Color(0xFFD6E1FA);
  static const _oscuro = Color(0xFF16307F);

  Map<String, VentaDepartamento> get _porIso => {for (final d in widget.datos) if (d.iso != null) d.iso!: d};

  Color _color(String iso, double maximo) {
    final d = _porIso[iso];
    if (d == null || d.total <= 0 || maximo <= 0) return _sinVentas;
    // Raíz cuadrada: la capital no "aplana" al resto de departamentos.
    return Color.lerp(_claro, _oscuro, math.sqrt(d.total / maximo))!;
  }

  @override
  void initState() {
    super.initState();
    if (_listas == null) {
      _cargarFormas().then((f) {
        if (mounted) setState(() => _listas = f);
      }, onError: (Object _) {
        if (mounted) setState(() => _fallo = true);
      });
    }
  }

  String? _enPunto(Offset posicion, List<_Forma> formas, _Proyeccion proy) {
    for (final f in formas) {
      if (proy.camino(f).contains(posicion)) return f.iso;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Builder(
      builder: (context) {
        if (_fallo) return const InlineBanner.error('No se pudo cargar el mapa.');
        final formas = _listas;
        if (formas == null) return const SizedBox(height: 240, child: Center(child: CircularProgressIndicator()));

        final maximo = widget.datos.fold<double>(0, (m, d) => math.max(m, d.total));
        final conVentas = widget.datos.where((d) => d.iso != null).toList();
        final activo = _hover ?? _elegido ?? (conVentas.isEmpty ? null : conVentas.first.iso);
        final detalle = activo == null ? null : _porIso[activo];
        final nombreActivo = activo == null ? null : formas.firstWhere((f) => f.iso == activo).nombre;

        final mapa = LayoutBuilder(builder: (context, c) {
          final tamano = Size(c.maxWidth, c.maxWidth * 1.05);
          final proy = _Proyeccion(formas, tamano);
          return MouseRegion(
            cursor: SystemMouseCursors.click,
            onHover: (e) {
              final iso = _enPunto(e.localPosition, formas, proy);
              if (iso != _hover) setState(() => _hover = iso);
            },
            onExit: (_) => setState(() => _hover = null),
            child: GestureDetector(
              onTapUp: (e) => setState(() => _elegido = _enPunto(e.localPosition, formas, proy) ?? _elegido),
              child: CustomPaint(
                key: const Key('mapa-guatemala'),
                size: tamano,
                painter: _PintorMapa(formas, proy, (iso) => _color(iso, maximo), activo),
              ),
            ),
          );
        });

        final panel = _PanelDepartamento(nombre: nombreActivo, detalle: detalle, ranking: conVentas.take(6).toList(), maximo: maximo,
            alElegir: (iso) => setState(() => _elegido = iso));

        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          LayoutBuilder(builder: (context, c) => c.maxWidth >= 760
              ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(flex: 3, child: mapa),
                  const SizedBox(width: 20),
                  Expanded(flex: 2, child: panel),
                ])
              : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [mapa, const SizedBox(height: 16), panel])),
          const SizedBox(height: 12),
          Row(children: [
            textoSecundario(context, 'Menos'),
            const SizedBox(width: 8),
            Expanded(
              child: Container(
                height: 8,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(99),
                  gradient: const LinearGradient(colors: [_claro, _oscuro]),
                ),
              ),
            ),
            const SizedBox(width: 8),
            textoSecundario(context, 'Más'),
          ]),
          const SizedBox(height: 6),
          Text('Límites departamentales: geoBoundaries · © colaboradores de OpenStreetMap (ODbL)',
              style: theme.textTheme.labelSmall?.copyWith(color: AppColors.textSecondary)),
        ]);
      },
    );
  }
}

class _PintorMapa extends CustomPainter {
  _PintorMapa(this.formas, this.proy, this.color, this.activo);

  final List<_Forma> formas;
  final _Proyeccion proy;
  final Color Function(String iso) color;
  final String? activo;

  @override
  void paint(Canvas canvas, Size size) {
    final borde = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = Colors.white;
    Path? resaltado;
    for (final f in formas) {
      final path = proy.camino(f);
      canvas.drawPath(path, Paint()..color = color(f.iso));
      canvas.drawPath(path, borde);
      if (f.iso == activo) resaltado = path;
    }
    if (resaltado != null) {
      canvas.drawPath(
          resaltado,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3
            ..color = const Color(0xFFF59E0B));
    }
  }

  @override
  bool shouldRepaint(_PintorMapa old) => old.activo != activo || old.formas != formas || old.color != color;
}

class _PanelDepartamento extends StatelessWidget {
  const _PanelDepartamento({required this.nombre, required this.detalle, required this.ranking, required this.maximo, required this.alElegir});

  final String? nombre;
  final VentaDepartamento? detalle;
  final List<VentaDepartamento> ranking;
  final double maximo;
  final ValueChanged<String> alElegir;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final d = detalle;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: const Color(0xFFF5F8FE), borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.border)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.place, color: AppColors.primary, size: 18),
            const SizedBox(width: 6),
            Expanded(child: Text(nombre ?? 'Elige un departamento', style: theme.textTheme.titleMedium)),
          ]),
          const SizedBox(height: 10),
          if (d == null)
            textoSecundario(context, nombre == null ? 'Pasa el mouse o toca el mapa.' : 'Sin ventas en este período.')
          else ...[
            Text(formatearMoneda(d.total), style: theme.textTheme.headlineSmall?.copyWith(color: AppColors.primary, fontWeight: FontWeight.w800)),
            textoSecundario(context, '${d.facturas} facturas · ${formatearNumero(d.unidades)} unidades · ${d.participacion.toStringAsFixed(1)} % del total'),
            if (d.productoTop != null) ...[
              const SizedBox(height: 12),
              textoSecundario(context, 'PRODUCTO MÁS VENDIDO'),
              const SizedBox(height: 2),
              Row(children: [
                const Icon(Icons.emoji_events_outlined, size: 18, color: AppColors.warning),
                const SizedBox(width: 6),
                Expanded(child: textoFuerte(context, d.productoTop!, lineas: 2)),
                textoSecundario(context, '${d.unidadesProductoTop} u.'),
              ]),
            ],
          ],
        ]),
      ),
      const SizedBox(height: 14),
      textoSecundario(context, 'DEPARTAMENTOS CON MÁS VENTAS'),
      const SizedBox(height: 6),
      for (final r in ranking)
        InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: r.iso == null ? null : () => alElegir(r.iso!),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                Expanded(child: Text(r.departamento, style: theme.textTheme.bodyMedium)),
                textoFuerte(context, formatearMoneda(r.total), lineas: 1),
              ]),
              const SizedBox(height: 4),
              BarraParticipacion(porcentaje: maximo == 0 ? 0 : r.total / maximo * 100, color: AppColors.primary),
            ]),
          ),
        ),
    ]);
  }
}
