class Producto {
  const Producto({
    required this.id,
    required this.codigo,
    required this.nombre,
    required this.precio,
    required this.stock,
    this.marca,
    this.categoria,
  });

  final int id;
  final String codigo;
  final String nombre;

  /// Precio informativo para mostrar; el precio que se cobra lo decide el servidor.
  final double precio;
  final int stock;
  final String? marca;
  final String? categoria;

  bool get disponible => stock > 0;

  factory Producto.fromJson(Map<String, dynamic> json) => Producto(
        id: json['id'] as int,
        codigo: json['codigo'] as String,
        nombre: json['nombre'] as String,
        precio: (json['precio'] as num).toDouble(),
        stock: json['stock'] as int,
        marca: json['marca'] as String?,
        categoria: json['categoria'] as String?,
      );
}

/// Especificación técnica: "Conexión" → "USB-C".
class Especificacion {
  const Especificacion(this.nombre, this.valor);

  final String nombre;
  final String valor;

  factory Especificacion.fromJson(Map<String, dynamic> j) =>
      Especificacion((j['nombre'] as String?) ?? '', (j['valor'] as String?) ?? '');

  Map<String, dynamic> toJson() => {'nombre': nombre, 'valor': valor};

  static List<Especificacion> lista(Object? json) =>
      ((json as List?) ?? const []).map((e) => Especificacion.fromJson(e as Map<String, dynamic>)).toList();
}

/// Ficha completa del producto (pantalla de detalle del catálogo).
class ProductoDetalle {
  const ProductoDetalle({
    required this.producto,
    this.descripcion,
    required this.garantiaMeses,
    required this.especificaciones,
  });

  final Producto producto;
  final String? descripcion;
  final int garantiaMeses;
  final List<Especificacion> especificaciones;

  factory ProductoDetalle.fromJson(Map<String, dynamic> j) => ProductoDetalle(
        producto: Producto.fromJson(j),
        descripcion: j['descripcion'] as String?,
        garantiaMeses: (j['garantiaMeses'] as int?) ?? 0,
        especificaciones: Especificacion.lista(j['especificaciones']),
      );
}

String garantiaLegible(int meses) => switch (meses) {
      0 => 'Sin garantía',
      12 => '1 año de garantía',
      24 => '2 años de garantía',
      36 => '3 años de garantía',
      1 => '1 mes de garantía',
      _ => '$meses meses de garantía',
    };
