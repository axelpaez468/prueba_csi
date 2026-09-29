import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../data/models/producto.dart';

/// Foto representativa del producto según su tipo (teclado, mouse, monitor...).
/// Las fotos van incluidas en la app (assets/productos, créditos en CREDITOS.md);
/// si un producto no coincide con ningún tipo, se muestra un ícono genérico.
class ProductoImagen extends StatelessWidget {
  const ProductoImagen({super.key, required this.producto, this.tamanoIcono = 40});

  final Producto producto;
  final double tamanoIcono;

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
    if (asset == null) return respaldo;

    return Image.asset(
      asset,
      fit: BoxFit.cover,
      // Sin stock: la foto se ve en escala de grises.
      color: producto.disponible ? null : Colors.grey,
      colorBlendMode: producto.disponible ? null : BlendMode.saturation,
      errorBuilder: (_, _, _) => respaldo,
    );
  }
}
