namespace Pedidos.Api.Domain;

public static class FormasPago
{
    public const string Efectivo = "EFECTIVO";
    public const string Tarjeta = "TARJETA";
    public const string Transferencia = "TRANSFERENCIA";

    public static readonly string[] Todas = { Efectivo, Tarjeta, Transferencia };
}

/// <summary>
/// Venta de contado. Cada pedido es también su factura (simulación de FEL): serie "A" y número = Id.
/// Los precios incluyen IVA: <see cref="Total"/> = <see cref="BaseImponible"/> + <see cref="Iva"/>.
/// </summary>
public class Pedido
{
    public const string SerieFactura = "A";
    public const decimal TasaIva = 0.12m;

    public int Id { get; set; }
    public int UsuarioId { get; set; }
    public int ClienteId { get; set; }
    public DateTime Fecha { get; set; }
    public string FormaPago { get; set; } = FormasPago.Efectivo;
    public decimal BaseImponible { get; set; }
    public decimal Iva { get; set; }
    public decimal Total { get; set; }

    /// <summary>Costo de la mercadería vendida (sin IVA), al costo promedio del momento.</summary>
    public decimal Costo { get; set; }

    /// <summary>Número de autorización simulado (en FEL lo asigna el certificador).</summary>
    public Guid Autorizacion { get; set; }

    // ---------- Entrega ----------

    public string? DireccionEntrega { get; set; }

    /// <summary>Nombre oficial del departamento de Guatemala (ver <c>Geografia</c>).</summary>
    public string? Departamento { get; set; }
    public string? Municipio { get; set; }

    // ---------- Pipeline ----------

    public string Estado { get; set; } = EstadosVenta.Nuevo;

    /// <summary>Desde cuándo está en la etapa actual (para ver qué se está atrasando).</summary>
    public DateTime EstadoDesde { get; set; }

    public Cliente? Cliente { get; set; }
    public List<PedidoDetalle> Detalles { get; set; } = new();
}
