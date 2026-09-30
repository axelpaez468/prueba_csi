namespace Pedidos.Api.Dtos;

/// <summary>Alta o edición de un usuario. El administrador nunca define la contraseña: el usuario la crea desde la invitación.</summary>
/// <param name="Telefono">8 dígitos de Guatemala; se guarda con el prefijo +502.</param>
public record GuardarUsuarioRequest(
    string? Nombre,
    string? Apellido,
    string? Telefono,
    string? Email,
    string? CodigoCorporativo,
    string? Rol);

public record UsuarioResponse(
    int Id,
    string Nombre,
    string Apellido,
    string NombreCompleto,
    string Email,
    string Telefono,
    string CodigoCorporativo,
    string Rol,
    bool Activo,
    string DosFactor,
    bool TieneContrasena,
    DateTime CreadoEn);
