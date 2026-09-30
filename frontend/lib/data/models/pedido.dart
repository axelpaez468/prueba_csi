/// Línea que se envía al crear un pedido: solo producto y cantidad.
/// No existe un campo de precio a propósito; el servidor lo toma de la base de datos.
class LineaPedido {
  const LineaPedido({required this.productoId, required this.cantidad});

  final int productoId;
  final int cantidad;

  Map<String, dynamic> toJson() => {'productoId': productoId, 'cantidad': cantidad};
}

/// Venta (pedido) y su factura tal como la devuelve la API (precios y total definitivos).
/// Los datos de factura son opcionales para seguir leyendo el contrato original del pedido.
class Pedido {
  const Pedido({
    required this.numero,
    required this.fecha,
    required this.total,
    required this.lineas,
    this.serie = 'A',
    this.autorizacion,
    this.clienteNit = 'CF',
    this.clienteNombre = 'Consumidor Final',
    this.clienteDireccion,
    this.vendedor,
    this.formaPago = 'EFECTIVO',
    double? baseImponible,
    double? iva,
  })  : baseImponible = baseImponible ?? total / 1.12,
        iva = iva ?? total - total / 1.12;

  final int numero;
  final DateTime fecha;
  final double total;
  final List<PedidoLinea> lineas;
  final String serie;

  /// Número de autorización (simulación de FEL).
  final String? autorizacion;
  final String clienteNit;
  final String clienteNombre;
  final String? clienteDireccion;
  final String? vendedor;
  final String formaPago;

  /// El precio incluye IVA: total = base imponible + IVA.
  final double baseImponible;
  final double iva;

  String get numeroFactura => '$serie-$numero';

  factory Pedido.fromJson(Map<String, dynamic> json) => Pedido(
        numero: json['numero'] as int,
        fecha: DateTime.parse(json['fecha'] as String),
        total: (json['total'] as num).toDouble(),
        lineas: (json['lineas'] as List)
            .map((l) => PedidoLinea.fromJson(l as Map<String, dynamic>))
            .toList(),
        serie: (json['serie'] as String?) ?? 'A',
        autorizacion: json['autorizacion'] as String?,
        clienteNit: (json['clienteNit'] as String?) ?? 'CF',
        clienteNombre: (json['clienteNombre'] as String?) ?? 'Consumidor Final',
        clienteDireccion: json['clienteDireccion'] as String?,
        vendedor: json['vendedor'] as String?,
        formaPago: (json['formaPago'] as String?) ?? 'EFECTIVO',
        baseImponible: (json['baseImponible'] as num?)?.toDouble(),
        iva: (json['iva'] as num?)?.toDouble(),
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
