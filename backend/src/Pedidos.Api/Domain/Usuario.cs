namespace Pedidos.Api.Domain;

public class Usuario
{
    public int Id { get; set; }

    /// <summary>
    /// Nombre para mostrar ("Nombre Apellido"); se mantiene a partir de <see cref="Nombre"/> y <see cref="Apellido"/>.
    /// El inicio de sesión es con <see cref="Email"/>.
    /// </summary>
    public string Username { get; set; } = string.Empty;

    public string Nombre { get; set; } = string.Empty;
    public string Apellido { get; set; } = string.Empty;

    /// <summary>Código interno del empleado (p. ej. VEN-0001), único y en mayúsculas.</summary>
    public string CodigoCorporativo { get; set; } = string.Empty;

    /// <summary>Un usuario desactivado no puede iniciar sesión; se conserva por su historial de pedidos.</summary>
    public bool Activo { get; set; } = true;

    public DateTime CreadoEn { get; set; }

    /// <summary>Siempre en minúsculas (se normaliza al guardar y al buscar).</summary>
    public string Email { get; set; } = string.Empty;

    public string PasswordHash { get; set; } = string.Empty;
    public string Rol { get; set; } = Roles.Vendedor;

    /// <summary>Teléfono de contacto en formato E.164 (+50255550101).</summary>
    public string? Telefono { get; set; }

    public string DosFactor { get; set; } = MetodosDosFactor.Ninguno;

    /// <summary>Secreto TOTP cifrado con AES-GCM (nunca en claro en la BD).</summary>
    public string? TotpSecretoCifrado { get; set; }

    /// <summary>Último paso TOTP aceptado: impide reutilizar el mismo código dentro de su ventana.</summary>
    public long? TotpUltimoPaso { get; set; }

    /// <summary>Configuración de 2FA en curso (aún sin confirmar).</summary>
    public string? TotpPendienteCifrado { get; set; }

    /// <summary>
    /// Los administradores no pueden operar sin segundo factor: si no lo tienen, el login los obliga a configurarlo.
    /// </summary>
    public bool DosFactorObligatorio => Rol == Roles.Admin;

    /// <summary>
    /// Se incrementa al cambiar la contraseña o el 2FA. Viaja en el JWT: los tokens emitidos antes
    /// del cambio dejan de ser válidos (cierra las sesiones abiertas en otros dispositivos).
    /// </summary>
    public int VersionSesion { get; set; }
}
