namespace Pedidos.Api.Dtos;

/// <param name="CostoUnitario">Costo por unidad sin IVA (el sistema agrega el 12 %).</param>
public record LineaOrdenRequest(int ProductoId, int Cantidad, decimal CostoUnitario);

public record CrearOrdenRequest(int ProveedorId, List<LineaOrdenRequest>? Lineas, string? Observaciones);

/// <param name="FacturaProveedor">Serie y número de la factura que entregó el proveedor.</param>
public record RecibirOrdenRequest(string? FacturaProveedor);

public record LineaOrdenResponse(int ProductoId, string Codigo, string Nombre, int Cantidad, decimal CostoUnitario, decimal Subtotal);

public record OrdenResponse(
    int Numero,
    DateTime Fecha,
    string Estado,
    int ProveedorId,
    string ProveedorNit,
    string ProveedorNombre,
    decimal Subtotal,
    decimal Iva,
    decimal Total,
    string? Observaciones,
    string CreadaPor,
    DateTime? FechaRecepcion,
    string? RecibidaPor,
    string? FacturaProveedor,
    List<LineaOrdenResponse> Lineas);

public record OrdenResumenResponse(
    int Numero, DateTime Fecha, string Estado, string ProveedorNombre, int Productos, decimal Total, string? FacturaProveedor);
