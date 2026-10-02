namespace Pedidos.Api.Dtos;

// Nullables a propósito: la validación la hacen los controladores con mensajes propios.

/// <param name="TokenDispositivo">Token de "confiar en este dispositivo"; si es válido se omite el 2FA.</param>
public record LoginRequest(string? Email, string? Password, string? TokenDispositivo = null);

/// <summary>Sesión iniciada.</summary>
/// <param name="CodigosRespaldo">Solo al terminar la configuración obligatoria del 2FA: se muestran una sola vez.</param>
public record LoginResponse(
    string Token,
    DateTime ExpiraEn,
    string Username,
    string Email,
    string Rol,
    string? TokenDispositivo = null,
    List<string>? CodigosRespaldo = null)
{
    public bool RequiereSegundoFactor => false;
}

/// <summary>Contraseña correcta, falta el segundo factor.</summary>
/// <param name="Desafio">Token de corta duración que solo sirve para completar este login.</param>
/// <param name="Metodo">"TOTP": pedir el código de la app. "CONFIGURAR": el 2FA es obligatorio y aún no está
/// configurado; se incluyen el secreto y la URI del QR para escanearlo antes de entrar.</param>
public record DesafioResponse(string Desafio, string Metodo, string? Secreto = null, string? Uri = null)
{
    public bool RequiereSegundoFactor => true;
}

public record VerificarSegundoFactorRequest(string? Desafio, string? Codigo, bool ConfiarDispositivo = false);

public record RecuperarPasswordRequest(string? Email);

public record RestablecerPasswordRequest(string? Token, string? NuevaPassword);

public record MensajeResponse(string Mensaje);
