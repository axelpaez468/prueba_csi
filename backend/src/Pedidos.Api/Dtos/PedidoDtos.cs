namespace Pedidos.Api.Dtos;

// El request solo acepta productos, cantidades, cliente y forma de pago. Si el cliente envía precio o total,
// el deserializador los descarta porque no existen en el contrato.
/// <param name="ClienteId">Opcional: si se omite, la venta es a consumidor final (CF).</param>
/// <param name="FormaPago">EFECTIVO (por defecto), TARJETA o TRANSFERENCIA. Todas las ventas son de contado.</param>
/// <param name="Departamento">Departamento de Guatemala de la entrega (GET /api/geografia). Si se envía, el municipio es obligatorio.</param>
/// <param name="Municipio">Municipio de ese departamento.</param>
public record CrearPedidoRequest(
    List<LineaPedidoRequest>? Lineas,
    int? ClienteId = null,
    string? FormaPago = null,
    string? DireccionEntrega = null,
    string? Departamento = null,
    string? Municipio = null);

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
    decimal Iva,
    string? DireccionEntrega,
    string? Departamento,
    string? Municipio,
    string Estado,
    DateTime EstadoDesde,
    List<HistorialEstadoResponse> Historial);

public record HistorialEstadoResponse(string Estado, DateTime Fecha, string? Usuario, string? Nota);

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
    decimal Total,
    string Estado,
    string? Departamento);

/// <summary>Tarjeta del tablero de pipeline.</summary>
public record TarjetaPipelineResponse(
    int Numero,
    DateTime Fecha,
    string ClienteNombre,
    string Vendedor,
    decimal Total,
    int Productos,
    string? Departamento,
    string? Municipio,
    string Estado,
    DateTime EstadoDesde,
    // La siguiente etapa, si el usuario puede llevarla ahí; si no, null.
    string? PuedeAvanzarA);

public record AvanzarEstadoRequest(string? Nota);
