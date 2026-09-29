namespace Pedidos.Api.Dtos;

// El request solo acepta productoId y cantidad. Si el cliente envía precio o total,
// el deserializador los descarta porque no existen en el contrato.
public record CrearPedidoRequest(List<LineaPedidoRequest>? Lineas);

public record LineaPedidoRequest(int ProductoId, int Cantidad);

public record PedidoResponse(int Numero, DateTime Fecha, int UsuarioId, decimal Total, List<PedidoLineaResponse> Lineas);

public record PedidoLineaResponse(
    int ProductoId,
    string Codigo,
    string Nombre,
    int Cantidad,
    decimal PrecioUnitario,
    decimal Subtotal);
