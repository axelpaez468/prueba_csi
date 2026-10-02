namespace Pedidos.Api.Domain;

public class PedidoDetalle
{
    public int PedidoId { get; set; }
    public int ProductoId { get; set; }
    public int Cantidad { get; set; }
    public decimal PrecioUnitario { get; set; }
    public decimal Subtotal { get; set; }

    /// <summary>Costo promedio (sin IVA) al momento de la venta.</summary>
    public decimal CostoUnitario { get; set; }

    public Producto? Producto { get; set; }
}
