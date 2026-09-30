import 'package:flutter/material.dart';

import '../../core/config/app_config.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/producto.dart';

/// Foto del producto: la principal que se subió a la API. Si el producto no tiene fotos (o no cargan),
/// se usa una ilustración incluida en la app según su tipo (assets/productos, créditos en CREDITOS.md)
/// o, si no coincide con ningún tipo, un ícono genérico.
class ProductoImagen extends StatelessWidget {
  const ProductoImagen({super.key, required this.producto, this.tamanoIcono = 40, this.imagenId, this.ajuste = BoxFit.cover});

  final Producto producto;
  final double tamanoIcono;

  /// Una foto concreta de la galería; por defecto, la principal.
  final int? imagenId;
  final BoxFit ajuste;

  static const _tipos = <(String, String, IconData)>[
    ('teclado', 'teclado', Icons.keyboard_outlined),
    ('mouse', 'mouse', Icons.mouse_outlined),
    ('monitor', 'monitor', Icons.desktop_windows_outlined),
    ('aud', 'audifonos', Icons.headphones_outlined),
    ('cam', 'webcam', Icons.videocam_outlined),
  ];

  static (String?, IconData) _resolver(String nombre) {
    final n = nombre.toLowerCase();
    for (final (clave, archivo, icono) in _tipos) {
      if (n.contains(clave)) return ('assets/productos/$archivo.jpg', icono);
    }
    return (null, Icons.inventory_2_outlined);
  }

  @override
  Widget build(BuildContext context) {
    final (asset, icono) = _resolver(producto.nombre);
    final respaldo = ColoredBox(
      color: const Color(0xFFE8EEF7),
      child: Center(child: Icon(icono, size: tamanoIcono, color: AppColors.primary.withValues(alpha: 0.75))),
    );
    final sinStock = !producto.disponible;
    final id = imagenId ?? producto.imagenId;
    final local = asset == null
        ? respaldo
        : Image.asset(
            asset,
            fit: BoxFit.cover,
            color: sinStock ? Colors.grey : null,
            colorBlendMode: sinStock ? BlendMode.saturation : null,
            errorBuilder: (_, _, _) => respaldo,
          );
    if (id == null || !AppConfig.isValid) return local;

    return Image.network(
      AppConfig.urlImagen(producto.id, id),
      fit: ajuste,
      // Sin stock: la foto se ve en escala de grises.
      color: sinStock ? Colors.grey : null,
      colorBlendMode: sinStock ? BlendMode.saturation : null,
      loadingBuilder: (_, child, progreso) => progreso == null ? child : ColoredBox(color: const Color(0xFFE8EEF7), child: child),
      errorBuilder: (_, _, _) => local,
    );
  }
}
