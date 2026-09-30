namespace Pedidos.Api.Domain;

public static class MetodosDosFactor
{
    public const string Ninguno = "NINGUNO";
    public const string Totp = "TOTP";
    public const string Sms = "SMS";
}

/// <summary>Códigos de respaldo del 2FA: de un solo uso, guardados como HMAC.</summary>
public class CodigoRespaldo
{
    public int Id { get; set; }
    public int UsuarioId { get; set; }
    public string CodigoHash { get; set; } = string.Empty;
    public DateTime? UsadoEn { get; set; }
}

public static class PropositosCodigo
{
    public const string Login = "LOGIN";
    public const string ActivarSms = "ACTIVAR_SMS";
}

/// <summary>Código de 6 dígitos enviado por SMS (login o activación del 2FA).</summary>
public class CodigoVerificacion
{
    public int Id { get; set; }
    public int UsuarioId { get; set; }
    public string Proposito { get; set; } = PropositosCodigo.Login;
    public string CodigoHash { get; set; } = string.Empty;
    public DateTime ExpiraEn { get; set; }
    public int Intentos { get; set; }
    public DateTime? UsadoEn { get; set; }
    public DateTime CreadoEn { get; set; }
}

/// <summary>Enlace de recuperación de contraseña: de un solo uso y con vencimiento.</summary>
public class TokenRecuperacion
{
    public int Id { get; set; }
    public int UsuarioId { get; set; }
    public string TokenHash { get; set; } = string.Empty;
    public DateTime ExpiraEn { get; set; }
    public DateTime? UsadoEn { get; set; }
    public DateTime CreadoEn { get; set; }
}

/// <summary>"Confiar en este dispositivo": permite omitir el 2FA durante un tiempo.</summary>
public class DispositivoConfiable
{
    public int Id { get; set; }
    public int UsuarioId { get; set; }
    public string TokenHash { get; set; } = string.Empty;
    public DateTime ExpiraEn { get; set; }
    public DateTime CreadoEn { get; set; }
}

/// <summary>Dispositivos desde los que el usuario ya inició sesión (para avisar de accesos nuevos).</summary>
public class DispositivoConocido
{
    public int Id { get; set; }
    public int UsuarioId { get; set; }
    public string Huella { get; set; } = string.Empty;
    public DateTime PrimerAcceso { get; set; }
    public DateTime UltimoAcceso { get; set; }
}

public static class EventosBitacora
{
    public const string LoginExitoso = "LOGIN_EXITOSO";
    public const string LoginFallido = "LOGIN_FALLIDO";
    public const string CuentaBloqueada = "CUENTA_BLOQUEADA";
    public const string SegundoFactorRequerido = "2FA_REQUERIDO";
    public const string SegundoFactorFallido = "2FA_FALLIDO";
    public const string CodigoRespaldoUsado = "CODIGO_RESPALDO_USADO";
    public const string RecuperacionSolicitada = "RECUPERACION_SOLICITADA";
    public const string PasswordRestablecida = "PASSWORD_RESTABLECIDA";
    public const string PasswordCambiada = "PASSWORD_CAMBIADA";
    public const string DosFactorActivado = "2FA_ACTIVADO";
    public const string DosFactorDesactivado = "2FA_DESACTIVADO";
    public const string CodigosRespaldoRegenerados = "CODIGOS_RESPALDO_REGENERADOS";
    public const string DispositivoNuevo = "DISPOSITIVO_NUEVO";
    public const string CuentaDesactivada = "CUENTA_DESACTIVADA";

    // Administración de usuarios (el registro guarda al administrador que actuó y el usuario afectado en Detalle).
    public const string UsuarioCreado = "USUARIO_CREADO";
    public const string UsuarioEditado = "USUARIO_EDITADO";
    public const string UsuarioActivado = "USUARIO_ACTIVADO";
    public const string UsuarioDesactivado = "USUARIO_DESACTIVADO";
    public const string UsuarioEliminado = "USUARIO_ELIMINADO";
    public const string InvitacionEnviada = "INVITACION_ENVIADA";
}

/// <summary>Bitácora de accesos y eventos de seguridad (auditoría).</summary>
public class RegistroAcceso
{
    public long Id { get; set; }
    public int? UsuarioId { get; set; }
    public string Email { get; set; } = string.Empty;
    public string Evento { get; set; } = string.Empty;
    public bool Exito { get; set; }
    public string? Ip { get; set; }
    public string? UserAgent { get; set; }
    public string? Detalle { get; set; }
    public DateTime Fecha { get; set; }
}
