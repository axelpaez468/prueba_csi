namespace Pedidos.Api.Domain;

public static class EstadosOrden
{
    public const string Pendiente = "PENDIENTE";
    public const string Recibida = "RECIBIDA";
    public const string Anulada = "ANULADA";
}

/// <summary>
/// Orden de compra a un proveedor. Se paga de contado al recibir la mercadería: en ese momento entra al
/// inventario (recalculando el costo promedio) y se registra la partida contable.
/// </summary>
public class OrdenCompra
{
    public int Id { get; set; }
    public int ProveedorId { get; set; }
    public DateTime Fecha { get; set; }
    public string Estado { get; set; } = EstadosOrden.Pendiente;

    /// <summary>Suma de las líneas, sin IVA.</summary>
    public decimal Subtotal { get; set; }
    public decimal Iva { get; set; }
    public decimal Total { get; set; }
    public string? Observaciones { get; set; }
    public int UsuarioId { get; set; }

    public DateTime? FechaRecepcion { get; set; }
    public int? RecibidaPorId { get; set; }

    /// <summary>Número de la factura del proveedor (se exige al recibir).</summary>
    public string? FacturaProveedor { get; set; }

    public Proveedor? Proveedor { get; set; }
    public List<OrdenCompraDetalle> Detalles { get; set; } = new();
}

public class OrdenCompraDetalle
{
    public int OrdenCompraId { get; set; }
    public int ProductoId { get; set; }
    public int Cantidad { get; set; }

    /// <summary>Costo unitario sin IVA.</summary>
    public decimal CostoUnitario { get; set; }
    public decimal Subtotal { get; set; }

    public Producto? Producto { get; set; }
}
