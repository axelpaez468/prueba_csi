namespace Pedidos.Api.Dtos;

// Nullables a propósito: la validación la hace el controlador con mensajes propios.
public record LoginRequest(string? Username, string? Password);

public record LoginResponse(string Token, DateTime ExpiraEn, string Username, string Rol);
