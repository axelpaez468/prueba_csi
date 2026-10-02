import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/util/formatters.dart';
import '../../data/models/producto.dart';
import 'producto_imagen.dart';

/// Avance automático de un PageView: pasa a la siguiente página cada [intervalo] y vuelve al inicio al final.
/// Se pausa mientras el mouse está encima o durante unos segundos después de que el usuario lo mueve a mano.
mixin _AutoAvance<W extends StatefulWidget> on State<W> {
  late PageController controlador;
  Timer? _timer;
  bool _pausado = false;
  int pagina = 0;

  int get paginas;
  Duration get intervalo;
  double get fraccion => 1;

  void iniciarAutoAvance() {
    controlador = PageController(viewportFraction: fraccion);
    _programar();
  }

  void _programar() {
    _timer?.cancel();
    if (paginas < 2) return;
    _timer = Timer.periodic(intervalo, (_) {
      if (_pausado || !controlador.hasClients) return;
      irA((pagina + 1) % paginas);
    });
  }

  void irA(int destino) {
    if (!controlador.hasClients) return;
    // Del último al primero se salta sin animar todo el recorrido hacia atrás.
    if (destino == 0 && pagina == paginas - 1 && paginas > 2) {
      controlador.jumpToPage(0);
    } else {
      controlador.animateToPage(destino, duration: const Duration(milliseconds: 450), curve: Curves.easeInOut);
    }
  }

  /// El usuario tomó el control: se reinicia la cuenta para que no salte enseguida.
  void interaccion() => _programar();

  void pausar(bool valor) => _pausado = valor;

  @override
  void dispose() {
    _timer?.cancel();
    controlador.dispose();
    super.dispose();
  }
}

/// Galería de fotos del producto con avance automático, flechas, indicadores y miniaturas.
class CarruselImagenes extends StatefulWidget {
  const CarruselImagenes({super.key, required this.producto, required this.imagenes, this.intervalo = const Duration(seconds: 4)});

  final Producto producto;
  final List<int> imagenes;
  final Duration intervalo;

  @override
  State<CarruselImagenes> createState() => _CarruselImagenesState();
}

class _CarruselImagenesState extends State<CarruselImagenes> with _AutoAvance<CarruselImagenes> {
  @override
  int get paginas => widget.imagenes.length;

  @override
  Duration get intervalo => widget.intervalo;

  @override
  void initState() {
    super.initState();
    iniciarAutoAvance();
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.producto;
    if (widget.imagenes.isEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: AspectRatio(aspectRatio: 4 / 3, child: ProductoImagen(producto: p, tamanoIcono: 72)),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MouseRegion(
          onEnter: (_) => pausar(true),
          onExit: (_) => pausar(false),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: AspectRatio(
              aspectRatio: 4 / 3,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ColoredBox(
                    color: Colors.white,
                    child: PageView.builder(
                      key: const Key('carrusel-imagenes'),
                      controller: controlador,
                      itemCount: paginas,
                      onPageChanged: (i) => setState(() => pagina = i),
                      itemBuilder: (_, i) => ProductoImagen(producto: p, imagenId: widget.imagenes[i], tamanoIcono: 72),
                    ),
                  ),
                  if (paginas > 1) ...[
                    Positioned(
                      left: 8,
                      top: 0,
                      bottom: 0,
                      child: Center(child: _Flecha(icono: Icons.chevron_left, alPresionar: () {
                        interaccion();
                        irA((pagina - 1 + paginas) % paginas);
                      })),
                    ),
                    Positioned(
                      right: 8,
                      top: 0,
                      bottom: 0,
                      child: Center(child: _Flecha(icono: Icons.chevron_right, alPresionar: () {
                        interaccion();
                        irA((pagina + 1) % paginas);
                      })),
                    ),
                    Positioned(
                      top: 10,
                      right: 10,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(99)),
                        child: Text('${pagina + 1} / $paginas',
                            style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
                      ),
                    ),
                    Positioned(
                      bottom: 10,
                      left: 0,
                      right: 0,
                      child: _Puntos(total: paginas, actual: pagina),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
        if (paginas > 1) ...[
          const SizedBox(height: 10),
          SizedBox(
            height: 64,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: paginas,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (_, i) => GestureDetector(
                onTap: () {
                  interaccion();
                  irA(i);
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 80,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: i == pagina ? AppColors.primary : AppColors.border, width: i == pagina ? 2.5 : 1),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: Opacity(
                      opacity: i == pagina ? 1 : 0.7,
                      child: ProductoImagen(producto: p, imagenId: widget.imagenes[i], tamanoIcono: 22),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// Carrusel de productos destacados del catálogo: avanza solo y muestra 1, 2 o 3 productos según el ancho.
class CarruselDestacados extends StatefulWidget {
  const CarruselDestacados({super.key, required this.productos, required this.alAbrir, this.intervalo = const Duration(seconds: 3)});

  final List<Producto> productos;
  final ValueChanged<Producto> alAbrir;
  final Duration intervalo;

  @override
  State<CarruselDestacados> createState() => _CarruselDestacadosState();
}

class _CarruselDestacadosState extends State<CarruselDestacados> with _AutoAvance<CarruselDestacados> {
  late double _fraccion;

  @override
  int get paginas => widget.productos.length;

  @override
  Duration get intervalo => widget.intervalo;

  @override
  double get fraccion => _fraccion;

  @override
  void initState() {
    super.initState();
    _fraccion = 0.85;
    iniciarAutoAvance();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Cuántos productos se ven a la vez depende del ancho (celular, tablet, escritorio).
    final ancho = MediaQuery.sizeOf(context).width;
    final nueva = ancho < 600 ? 0.85 : ancho < 1000 ? 0.5 : 0.34;
    if (nueva != _fraccion) {
      _fraccion = nueva;
      final anterior = controlador;
      controlador = PageController(viewportFraction: nueva, initialPage: pagina);
      WidgetsBinding.instance.addPostFrameCallback((_) => anterior.dispose());
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return MouseRegion(
      onEnter: (_) => pausar(true),
      onExit: (_) => pausar(false),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            const Icon(Icons.local_fire_department_outlined, color: AppColors.accent),
            const SizedBox(width: 8),
            Expanded(child: Text('Destacados', style: theme.textTheme.titleMedium)),
            if (paginas > 1) ...[
              _Flecha(icono: Icons.chevron_left, alPresionar: () {
                interaccion();
                irA((pagina - 1 + paginas) % paginas);
              }),
              const SizedBox(width: 6),
              _Flecha(icono: Icons.chevron_right, alPresionar: () {
                interaccion();
                irA((pagina + 1) % paginas);
              }),
            ],
          ]),
          const SizedBox(height: 12),
          SizedBox(
            height: 230,
            child: PageView.builder(
              key: const Key('carrusel-destacados'),
              controller: controlador,
              padEnds: false,
              itemCount: paginas,
              onPageChanged: (i) => setState(() => pagina = i),
              itemBuilder: (_, i) => Padding(
                padding: const EdgeInsets.only(right: 12),
                child: _TarjetaDestacado(producto: widget.productos[i], alAbrir: () => widget.alAbrir(widget.productos[i])),
              ),
            ),
          ),
          const SizedBox(height: 10),
          _Puntos(total: paginas, actual: pagina, oscuro: true),
        ],
      ),
    );
  }
}

class _TarjetaDestacado extends StatelessWidget {
  const _TarjetaDestacado({required this.producto, required this.alAbrir});

  final Producto producto;
  final VoidCallback alAbrir;

  @override
  Widget build(BuildContext context) {
    final p = producto;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: alAbrir,
        child: Stack(fit: StackFit.expand, children: [
          ProductoImagen(producto: p, tamanoIcono: 56),
          // Degradado para que el texto se lea sobre cualquier foto.
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.transparent, Colors.transparent, Color(0xDD0E1C2E)],
              ),
            ),
          ),
          Positioned(
            left: 14,
            right: 14,
            bottom: 12,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (p.categoria != null)
                Text(p.categoria!.toUpperCase(),
                    style: const TextStyle(color: Colors.white70, fontSize: 11, letterSpacing: 0.8, fontWeight: FontWeight.w600)),
              Text(p.nombre,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Row(children: [
                Flexible(
                  child: Text(formatearMoneda(p.precio),
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600)),
                ),
                const SizedBox(width: 8),
                Text(p.disponible ? 'Ver detalle ›' : 'Agotado',
                    style: TextStyle(color: p.disponible ? const Color(0xFF9FE3D0) : Colors.white70, fontSize: 12)),
              ]),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _Flecha extends StatelessWidget {
  const _Flecha({required this.icono, required this.alPresionar});

  final IconData icono;
  final VoidCallback alPresionar;

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.white.withValues(alpha: 0.9),
        shape: const CircleBorder(side: BorderSide(color: AppColors.border)),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: alPresionar,
          child: Padding(padding: const EdgeInsets.all(6), child: Icon(icono, color: AppColors.textPrimary)),
        ),
      );
}

class _Puntos extends StatelessWidget {
  const _Puntos({required this.total, required this.actual, this.oscuro = false});

  final int total;
  final int actual;
  final bool oscuro;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var i = 0; i < total; i++)
            AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              margin: const EdgeInsets.symmetric(horizontal: 3),
              width: i == actual ? 18 : 7,
              height: 7,
              decoration: BoxDecoration(
                color: oscuro
                    ? (i == actual ? AppColors.primary : AppColors.border)
                    : (i == actual ? Colors.white : Colors.white54),
                borderRadius: BorderRadius.circular(99),
              ),
            ),
        ],
      );
}
