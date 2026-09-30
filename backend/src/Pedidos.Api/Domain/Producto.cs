namespace Pedidos.Api.Domain;

public class Producto
{
    public int Id { get; set; }
    public string Codigo { get; set; } = string.Empty;
    public string Nombre { get; set; } = string.Empty;

    /// <summary>Precio de venta, con IVA incluido.</summary>
    public decimal Precio { get; set; }
    public int Stock { get; set; }

    /// <summary>Costo promedio ponderado sin IVA: lo recalcula cada entrada de mercadería.</summary>
    public decimal CostoPromedio { get; set; }

    /// <summary>Por debajo de esta existencia el producto se marca para reabastecer.</summary>
    public int StockMinimo { get; set; }

    /// <summary>Un producto inactivo no aparece en el catálogo ni se puede vender o comprar.</summary>
    public bool Activo { get; set; } = true;

    // ---------- Ficha del producto (lo que ve el vendedor en el catálogo) ----------

    public string? Marca { get; set; }
    public string? Categoria { get; set; }

    /// <summary>Descripción comercial detallada; admite párrafos (saltos de línea).</summary>
    public string? Descripcion { get; set; }

    /// <summary>0 = sin garantía.</summary>
    public int GarantiaMeses { get; set; }

    /// <summary>Especificaciones técnicas (se guardan como JSON en una sola columna).</summary>
    public List<Especificacion> Especificaciones { get; set; } = new();
}

/// <summary>Especificación técnica: "Conexión" → "USB-C y Bluetooth 5.1".</summary>
public record Especificacion(string Nombre, string Valor);
