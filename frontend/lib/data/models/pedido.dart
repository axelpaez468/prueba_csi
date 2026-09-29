/// Línea que se envía al crear un pedido: solo producto y cantidad.
/// No existe un campo de precio a propósito; el servidor lo toma de la base de datos.
class LineaPedido {
  const LineaPedido({required this.productoId, required this.cantidad});

  final int productoId;
  final int cantidad;

  Map<String, dynamic> toJson() => {'productoId': productoId, 'cantidad': cantidad};
}

/// Pedido tal como lo devuelve la API (precios y total definitivos).
class Pedido {
  const Pedido({
    required this.numero,
    required this.fecha,
    required this.total,
    required this.lineas,
  });

  final int numero;
  final DateTime fecha;
  final double total;
  final List<PedidoLinea> lineas;

  factory Pedido.fromJson(Map<String, dynamic> json) => Pedido(
        numero: json['numero'] as int,
        fecha: DateTime.parse(json['fecha'] as String),
        total: (json['total'] as num).toDouble(),
        lineas: (json['lineas'] as List)
            .map((l) => PedidoLinea.fromJson(l as Map<String, dynamic>))
            .toList(),
      );
}

class PedidoLinea {
  const PedidoLinea({
    required this.productoId,
    required this.codigo,
    required this.nombre,
    required this.cantidad,
    required this.precioUnitario,
    required this.subtotal,
  });

  final int productoId;
  final String codigo;
  final String nombre;
  final int cantidad;
  final double precioUnitario;
  final double subtotal;

  factory PedidoLinea.fromJson(Map<String, dynamic> json) => PedidoLinea(
        productoId: json['productoId'] as int,
        codigo: json['codigo'] as String,
        nombre: json['nombre'] as String,
        cantidad: json['cantidad'] as int,
        precioUnitario: (json['precioUnitario'] as num).toDouble(),
        subtotal: (json['subtotal'] as num).toDouble(),
      );
}
