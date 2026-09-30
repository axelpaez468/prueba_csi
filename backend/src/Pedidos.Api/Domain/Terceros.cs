namespace Pedidos.Api.Domain;

/// <summary>Cliente de ventas. "CF" (consumidor final) es un cliente más, sembrado con el NIT "CF".</summary>
public class Cliente
{
    public const string NitConsumidorFinal = "CF";

    public int Id { get; set; }

    /// <summary>Sin guiones ni espacios y en mayúsculas (p. ej. "1234567K"), o "CF".</summary>
    public string Nit { get; set; } = string.Empty;
    public string Nombre { get; set; } = string.Empty;
    public string? Direccion { get; set; }
    public string? Telefono { get; set; }
    public string? Email { get; set; }
    public bool Activo { get; set; } = true;
    public DateTime CreadoEn { get; set; }
}

public class Proveedor
{
    public int Id { get; set; }
    public string Nit { get; set; } = string.Empty;
    public string Nombre { get; set; } = string.Empty;
    public string? Contacto { get; set; }
    public string? Telefono { get; set; }
    public string? Email { get; set; }
    public string? Direccion { get; set; }
    public bool Activo { get; set; } = true;
    public DateTime CreadoEn { get; set; }
}
