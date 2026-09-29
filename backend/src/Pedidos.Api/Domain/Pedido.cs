namespace Pedidos.Api.Domain;

public class Pedido
{
    public int Id { get; set; }
    public int UsuarioId { get; set; }
    public DateTime Fecha { get; set; }
    public decimal Total { get; set; }

    public List<PedidoDetalle> Detalles { get; set; } = new();
}
