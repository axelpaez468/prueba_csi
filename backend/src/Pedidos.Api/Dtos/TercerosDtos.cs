namespace Pedidos.Api.Dtos;

/// <param name="Nit">NIT de Guatemala (con o sin guion) o "CF" para consumidor final.</param>
public record GuardarClienteRequest(string? Nit, string? Nombre, string? Direccion, string? Telefono, string? Email, bool? Activo);

public record ClienteResponse(
    int Id, string Nit, string NitFormateado, string Nombre, string? Direccion, string? Telefono, string? Email,
    bool Activo, bool EsConsumidorFinal);

public record GuardarProveedorRequest(
    string? Nit, string? Nombre, string? Contacto, string? Telefono, string? Email, string? Direccion, bool? Activo);

public record ProveedorResponse(
    int Id, string Nit, string NitFormateado, string Nombre, string? Contacto, string? Telefono, string? Email,
    string? Direccion, bool Activo);
