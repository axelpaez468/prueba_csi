using System.Security.Claims;

namespace Pedidos.Api.Security;

/// <summary>Nombres de claims tal como viajan en el token (sin el mapeo a URIs de .NET).</summary>
public static class JwtClaims
{
    public const string UserId = "sub";
    public const string Username = "unique_name";
    public const string Email = "email";
    public const string Role = "role";

    /// <summary>Versión de sesión del usuario al emitir el token (ver Usuario.VersionSesion).</summary>
    public const string VersionSesion = "sv";

    public static int GetUsuarioId(this ClaimsPrincipal user) =>
        int.Parse(user.FindFirst(UserId)?.Value
                  ?? throw new InvalidOperationException("El token no contiene el id de usuario."));
}
