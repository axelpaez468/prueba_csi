namespace Pedidos.Api.Dtos;

// El request solo acepta productos, cantidades, cliente y forma de pago. Si el cliente envía precio o total,
// el deserializador los descarta porque no existen en el contrato.
/// <param name="ClienteId">Opcional: si se omite, la venta es a consumidor final (CF).</param>
/// <param name="FormaPago">EFECTIVO (por defecto), TARJETA o TRANSFERENCIA. Todas las ventas son de contado.</param>
public record CrearPedidoRequest(List<LineaPedidoRequest>? Lineas, int? ClienteId = null, string? FormaPago = null);

public record LineaPedidoRequest(int ProductoId, int Cantidad);

/// <summary>
/// Venta y su factura (simulación de FEL). Los primeros campos son el contrato original del pedido;
/// los demás se agregaron con el módulo de ventas.
/// </summary>
public record PedidoResponse(
    int Numero,
    DateTime Fecha,
    int UsuarioId,
    decimal Total,
    List<PedidoLineaResponse> Lineas,
    string Serie,
    Guid Autorizacion,
    int ClienteId,
    string ClienteNit,
    string ClienteNombre,
    string? ClienteDireccion,
    string Vendedor,
    string FormaPago,
    decimal BaseImponible,
    decimal Iva);

public record PedidoLineaResponse(
    int ProductoId,
    string Codigo,
    string Nombre,
    int Cantidad,
    decimal PrecioUnitario,
    decimal Subtotal);

public record VentaResumenResponse(
    int Numero,
    string Serie,
    DateTime Fecha,
    string ClienteNit,
    string ClienteNombre,
    string Vendedor,
    string FormaPago,
    int Productos,
    decimal Total);
