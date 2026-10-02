namespace Pedidos.Api.Domain;

/// <summary>El primer dígito del código define el tipo: 1 activo, 2 pasivo, 3 capital, 4 ingreso, 5 costo, 6 gasto.</summary>
public static class TiposCuenta
{
    public const string Activo = "ACTIVO";
    public const string Pasivo = "PASIVO";
    public const string Capital = "CAPITAL";
    public const string Ingreso = "INGRESO";
    public const string Costo = "COSTO";
    public const string Gasto = "GASTO";

    public static string? DesdeCodigo(string codigo) => codigo.Length == 0 ? null : codigo[0] switch
    {
        '1' => Activo,
        '2' => Pasivo,
        '3' => Capital,
        '4' => Ingreso,
        '5' => Costo,
        '6' => Gasto,
        _ => null
    };

    /// <summary>Activos, costos y gastos aumentan por el debe; pasivos, capital e ingresos por el haber.</summary>
    public static bool EsDeudora(string tipo) => tipo is Activo or Costo or Gasto;
}

/// <summary>Cuentas que usan las partidas automáticas. No se pueden desactivar.</summary>
public static class CuentasSistema
{
    public const string Caja = "1101";
    public const string Bancos = "1102";
    public const string Inventario = "1103";
    public const string IvaPorCobrar = "1104";
    public const string IvaPorPagar = "2102";
    public const string Capital = "3101";
    public const string Ventas = "4101";
    public const string OtrosIngresos = "4102";
    public const string CostoVentas = "5101";
    public const string FaltantesInventario = "6104";

    public static readonly string[] Todas =
        { Caja, Bancos, Inventario, IvaPorCobrar, IvaPorPagar, Capital, Ventas, OtrosIngresos, CostoVentas, FaltantesInventario };
}

public class CuentaContable
{
    public int Id { get; set; }
    public string Codigo { get; set; } = string.Empty;
    public string Nombre { get; set; } = string.Empty;
    public string Tipo { get; set; } = string.Empty;
    public bool Activa { get; set; } = true;
}

public static class OrigenesPartida
{
    public const string Apertura = "APERTURA";
    public const string Venta = "VENTA";
    public const string Compra = "COMPRA";
    public const string Ajuste = "AJUSTE";
    public const string Manual = "MANUAL";
}

/// <summary>Partida (asiento) de libro diario: la suma del debe siempre es igual a la del haber.</summary>
public class Partida
{
    public int Id { get; set; }

    /// <summary>Fecha contable (hora de Guatemala).</summary>
    public DateOnly Fecha { get; set; }
    public string Concepto { get; set; } = string.Empty;
    public string Origen { get; set; } = OrigenesPartida.Manual;

    /// <summary>Id del documento de origen (venta, orden de compra, movimiento de inventario).</summary>
    public long? ReferenciaId { get; set; }
    public int? UsuarioId { get; set; }
    public DateTime CreadoEn { get; set; }
    public decimal Total { get; set; }

    public List<PartidaDetalle> Detalles { get; set; } = new();
}

public class PartidaDetalle
{
    public long Id { get; set; }
    public int PartidaId { get; set; }
    public int CuentaId { get; set; }
    public decimal Debe { get; set; }
    public decimal Haber { get; set; }

    public CuentaContable? Cuenta { get; set; }
}
