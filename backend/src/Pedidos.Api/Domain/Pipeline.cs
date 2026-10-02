namespace Pedidos.Api.Domain;

/// <summary>
/// Etapas de una venta, en orden. Solo se avanza de una etapa a la siguiente, y cada etapa la mueve el área que
/// le corresponde: el vendedor revisa, administración o contabilidad autoriza y bodega despacha y entrega.
/// </summary>
public static class EstadosVenta
{
    public const string Nuevo = "NUEVO";
    public const string Revisado = "REVISADO";
    public const string Autorizado = "AUTORIZADO";
    public const string Despachado = "DESPACHADO";
    public const string EnCamino = "EN_CAMINO";
    public const string Entregado = "ENTREGADO";

    public static readonly string[] Orden = { Nuevo, Revisado, Autorizado, Despachado, EnCamino, Entregado };

    public static string? Siguiente(string estado)
    {
        var i = Array.IndexOf(Orden, estado);
        return i < 0 || i == Orden.Length - 1 ? null : Orden[i + 1];
    }

    /// <summary>Roles que pueden llevar una venta A esta etapa.</summary>
    public static string[] QuienPuedeLlevarA(string estado) => estado switch
    {
        Revisado => new[] { Roles.Vendedor, Roles.Admin },
        Autorizado => new[] { Roles.Admin, Roles.Contador },
        Despachado or EnCamino or Entregado => new[] { Roles.Bodega, Roles.Admin },
        _ => Array.Empty<string>()
    };

    /// <summary>
    /// Probabilidad de cierre con la que arranca cada etapa (el administrador la puede cambiar). Una venta entregada
    /// y cobrada ya está cerrada: siempre 100 %.
    /// </summary>
    public static readonly IReadOnlyDictionary<string, decimal> ProbabilidadInicial = new Dictionary<string, decimal>
    {
        [Nuevo] = 10, [Revisado] = 25, [Autorizado] = 50, [Despachado] = 75, [EnCamino] = 90, [Entregado] = 100
    };

    public static string Nombre(string estado) => estado switch
    {
        Nuevo => "Nuevo",
        Revisado => "Revisado",
        Autorizado => "Autorizado",
        Despachado => "Despachado",
        EnCamino => "En camino",
        Entregado => "Entregado / cobrado",
        _ => estado
    };
}

/// <summary>Probabilidad de cierre de una etapa del pipeline (0 a 100 %), para el pronóstico de ventas.</summary>
public class EtapaPipeline
{
    public string Estado { get; set; } = EstadosVenta.Nuevo;
    public decimal Probabilidad { get; set; }
    public DateTime? ActualizadoEn { get; set; }
    public string? ActualizadoPor { get; set; }
}

/// <summary>Cada cambio de etapa de una venta: quién, cuándo y con qué nota (trazabilidad del pipeline).</summary>
public class PedidoHistorial
{
    public long Id { get; set; }
    public int PedidoId { get; set; }
    public string Estado { get; set; } = EstadosVenta.Nuevo;
    public DateTime Fecha { get; set; }
    public int? UsuarioId { get; set; }
    public string? Nota { get; set; }
}
