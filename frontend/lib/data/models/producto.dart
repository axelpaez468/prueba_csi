class Producto {
  const Producto({
    required this.id,
    required this.codigo,
    required this.nombre,
    required this.precio,
    required this.stock,
  });

  final int id;
  final String codigo;
  final String nombre;

  /// Precio informativo para mostrar; el precio que se cobra lo decide el servidor.
  final double precio;
  final int stock;

  bool get disponible => stock > 0;

  factory Producto.fromJson(Map<String, dynamic> json) => Producto(
        id: json['id'] as int,
        codigo: json['codigo'] as String,
        nombre: json['nombre'] as String,
        precio: (json['precio'] as num).toDouble(),
        stock: json['stock'] as int,
      );
}
