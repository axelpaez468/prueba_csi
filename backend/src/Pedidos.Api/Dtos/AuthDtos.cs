namespace Pedidos.Api.Dtos;

// Nullables a propósito: la validación la hacen los controladores con mensajes propios.

/// <param name="TokenDispositivo">Token de "confiar en este dispositivo"; si es válido se omite el 2FA.</param>
public record LoginRequest(string? Email, string? Password, string? TokenDispositivo = null);

/// <summary>Sesión iniciada.</summary>
public record LoginResponse(
    string Token,
    DateTime ExpiraEn,
    string Username,
    string Email,
    string Rol,
    string? TokenDispositivo = null)
{
    public bool RequiereSegundoFactor => false;
}

/// <summary>Contraseña correcta, falta el segundo factor.</summary>
/// <param name="Desafio">Token de corta duración que solo sirve para completar este login.</param>
/// <param name="Destino">Teléfono enmascarado, si el método es SMS.</param>
public record DesafioResponse(string Desafio, string Metodo, string? Destino)
{
    public bool RequiereSegundoFactor => true;
}

public record VerificarSegundoFactorRequest(string? Desafio, string? Codigo, bool ConfiarDispositivo = false);

public record ReenviarCodigoRequest(string? Desafio);

public record RecuperarPasswordRequest(string? Email);

public record RestablecerPasswordRequest(string? Token, string? NuevaPassword);

public record MensajeResponse(string Mensaje);
