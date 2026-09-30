namespace Pedidos.Api.Domain;

public static class TiposMovimiento
{
    public const string Inicial = "INICIAL";
    public const string Venta = "VENTA";
    public const string Compra = "COMPRA";
    public const string AjusteEntrada = "AJUSTE_ENTRADA";
    public const string AjusteSalida = "AJUSTE_SALIDA";
}

/// <summary>
/// Kardex: cada entrada o salida de mercadería con el saldo y el costo promedio que resultan.
/// Nunca se edita ni se borra; el saldo de <see cref="Producto.Stock"/> siempre coincide con el último movimiento.
/// </summary>
public class MovimientoInventario
{
    public long Id { get; set; }
    public int ProductoId { get; set; }
    public DateTime Fecha { get; set; }
    public string Tipo { get; set; } = string.Empty;

    /// <summary>Positiva para entradas y negativa para salidas.</summary>
    public int Cantidad { get; set; }

    /// <summary>Costo sin IVA de la unidad que entra o sale.</summary>
    public decimal CostoUnitario { get; set; }

    /// <summary>Existencia después del movimiento.</summary>
    public int Saldo { get; set; }

    /// <summary>Costo promedio ponderado después del movimiento.</summary>
    public decimal CostoPromedio { get; set; }

    /// <summary>Documento que lo originó: "Factura A-15", "OC-3", "Ajuste: producto dañado"...</summary>
    public string Referencia { get; set; } = string.Empty;
    public int? UsuarioId { get; set; }
}
