using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Options;
using Pedidos.Api.Data;
using Pedidos.Api.Domain;
using Pedidos.Api.Errors;
using Pedidos.Api.Notificaciones;
using Pedidos.Api.Security;
using Pedidos.Api.Services.Usuarios;

namespace Pedidos.Api.Services.Seguridad;

public class FrontendOptions
{
    public const string Section = "Frontend";

    /// <summary>URL pública del frontend, para armar los enlaces de los correos.</summary>
    public string UrlPublica { get; set; } = "http://localhost:8080";
}

/// <summary>
/// "Olvidé mi contraseña": enlace de un solo uso que vence en 30 minutos. La respuesta es siempre la misma,
/// exista o no el correo, para no revelar qué cuentas existen.
/// </summary>
public class RecuperacionService
{
    public static readonly TimeSpan VigenciaEnlace = TimeSpan.FromMinutes(30);

    /// <summary>La invitación a un usuario nuevo dura más: puede no revisar el correo de inmediato.</summary>
    public static readonly TimeSpan VigenciaInvitacion = TimeSpan.FromHours(48);

    private readonly AppDbContext _db;
    private readonly Cifrador _cifrador;
    private readonly PoliticaPassword _politica;
    private readonly BitacoraService _bitacora;
    private readonly IEnviadorCorreo _correo;
    private readonly FrontendOptions _frontend;
    private readonly TimeProvider _time;

    public RecuperacionService(AppDbContext db, Cifrador cifrador, PoliticaPassword politica, BitacoraService bitacora,
        IEnviadorCorreo correo, IOptions<FrontendOptions> frontend, TimeProvider time)
    {
        _db = db;
        _cifrador = cifrador;
        _politica = politica;
        _bitacora = bitacora;
        _correo = correo;
        _frontend = frontend.Value;
        _time = time;
    }

    private DateTime Ahora => _time.GetUtcNow().UtcDateTime;

    public async Task SolicitarAsync(string email, ContextoCliente ctx, CancellationToken ct)
    {
        email = AuthService.NormalizarEmail(email);
        var usuario = await _db.Usuarios.AsNoTracking().FirstOrDefaultAsync(u => u.Email == email, ct);
        // Una cuenta desactivada no recibe enlaces (la respuesta al cliente es la misma de siempre).
        var procede = usuario is { Activo: true };
        _bitacora.Registrar(EventosBitacora.RecuperacionSolicitada, procede, email, ctx, usuario?.Id);

        if (procede)
        {
            var enlace = await CrearEnlaceAsync(usuario!.Id, VigenciaEnlace, ct);
            _correo.Encolar(usuario.Email, new PlantillaCorreo(
                "Restablece tu contraseña",
                "Restablece tu contraseña",
                $"Hola {usuario.Nombre}:",
                new[] { "Recibimos una solicitud para restablecer la contraseña de tu cuenta. Usa el botón para crear una nueva." },
                TipoCorreo.Seguridad,
                new[] { ("Solicitado desde", ctx.Dispositivo), ("Dirección IP", ctx.Ip ?? "desconocida") },
                "Crear una nueva contraseña",
                enlace,
                $"El enlace vence en {VigenciaEnlace.TotalMinutes:0} minutos y funciona una sola vez.",
                "Si no fuiste tú, ignora este correo: tu contraseña no cambiará."));
        }

        await _db.SaveChangesAsync(ct);
    }

    /// <summary>Correo de bienvenida para un usuario creado por el administrador: define su contraseña con el enlace.</summary>
    public async Task EnviarInvitacionAsync(Usuario usuario, ContextoCliente ctx, CancellationToken ct)
    {
        // Si aún no tiene contraseña, el enlace abre la pantalla de bienvenida ("crea tu contraseña").
        var enlace = await CrearEnlaceAsync(usuario.Id, VigenciaInvitacion, ct,
            invitacion: !UsuarioService.TieneContrasena(usuario));
        await _db.SaveChangesAsync(ct);
        var parrafos = new List<string> { "Se creó tu cuenta en el Sistema de Pedidos. Para activarla, crea tu propia contraseña con el botón." };
        if (usuario.DosFactorObligatorio)
            parrafos.Add("En tu primer inicio de sesión configurarás la verificación en dos pasos con Google Authenticator " +
                         "(gratis en Play Store o App Store): ten tu teléfono a mano.");
        _correo.Encolar(usuario.Email, new PlantillaCorreo(
            "Bienvenido al Sistema de Pedidos",
            "¡Bienvenido al equipo!",
            $"Hola {usuario.Nombre}:",
            parrafos,
            TipoCorreo.Informativo,
            new[] { ("Correo de acceso", usuario.Email), ("Código corporativo", usuario.CodigoCorporativo), ("Rol", NombreRol(usuario.Rol)) },
            "Crear mi contraseña",
            enlace,
            $"El enlace vence en {VigenciaInvitacion.TotalHours:0} horas y funciona una sola vez.",
            "Si no esperabas este correo, ignóralo."));
    }

    /// <summary>
    /// Solo un enlace vigente por usuario: crear uno invalida los anteriores. En la BD se guarda solo la huella
    /// del token, así que una filtración de la BD no sirve para usar el enlace.
    /// </summary>
    private async Task<string> CrearEnlaceAsync(int usuarioId, TimeSpan vigencia, CancellationToken ct,
        bool invitacion = false)
    {
        await _db.TokensRecuperacion
            .Where(t => t.UsuarioId == usuarioId && t.UsadoEn == null)
            .ExecuteUpdateAsync(s => s.SetProperty(t => t.UsadoEn, Ahora), ct);

        var token = Aleatorio.Token();
        _db.TokensRecuperacion.Add(new TokenRecuperacion
        {
            UsuarioId = usuarioId,
            TokenHash = _cifrador.Huella(token),
            CreadoEn = Ahora,
            ExpiraEn = Ahora + vigencia
        });
        return $"{_frontend.UrlPublica.TrimEnd('/')}/?restablecer={token}" + (invitacion ? "&invitacion=1" : "");
    }

    public async Task RestablecerAsync(string token, string nuevaPassword, ContextoCliente ctx, CancellationToken ct)
    {
        var huella = _cifrador.Huella(token);
        var registro = await _db.TokensRecuperacion.FirstOrDefaultAsync(t => t.TokenHash == huella, ct);
        if (registro is null || registro.UsadoEn is not null || registro.ExpiraEn <= Ahora)
            throw new BusinessRuleException("El enlace no es válido o ya expiró. Solicita uno nuevo.");

        var usuario = await _db.Usuarios.FirstAsync(u => u.Id == registro.UsuarioId, ct);
        if (!usuario.Activo)
            throw new BusinessRuleException("El enlace no es válido o ya expiró. Solicita uno nuevo.");
        var error = await _politica.ValidarAsync(nuevaPassword, usuario.Email, ct);
        if (error is not null)
            throw new BusinessRuleException(error);

        var activacion = !UsuarioService.TieneContrasena(usuario);
        registro.UsadoEn = Ahora;
        await AplicarNuevaPasswordAsync(_db, usuario, nuevaPassword, ct);
        _bitacora.Registrar(EventosBitacora.PasswordRestablecida, true, usuario.Email, ctx, usuario.Id);
        await _db.SaveChangesAsync(ct);

        if (activacion)
        {
            _correo.Encolar(usuario.Email, new PlantillaCorreo(
                "Tu cuenta está activa",
                "Tu cuenta está activa",
                $"Hola {usuario.Nombre}:",
                new[]
                {
                    "Creaste tu contraseña y tu cuenta del Sistema de Pedidos quedó lista.",
                    "Al iniciar sesión configurarás Google Authenticator: escanea el código QR con la app y escribe el código de 6 dígitos."
                },
                TipoCorreo.Exito,
                new[] { ("Correo de acceso", usuario.Email) },
                "Iniciar sesión",
                _frontend.UrlPublica,
                Aviso: "Si no fuiste tú, contacta al administrador de inmediato."));
            return;
        }

        _correo.Encolar(usuario.Email, new PlantillaCorreo(
            "Tu contraseña fue cambiada",
            "Restableciste tu contraseña",
            $"Hola {usuario.Nombre}:",
            new[] { "La contraseña de tu cuenta se restableció con el enlace que te enviamos. Cerramos las sesiones abiertas en otros dispositivos." },
            TipoCorreo.Seguridad,
            new[] { ("Fecha", PlantillaCorreo.Hora(Ahora)), ("Desde", ctx.Dispositivo) },
            Aviso: "Si no fuiste tú, contacta al administrador de inmediato."));
    }

    /// <summary>
    /// Guarda la nueva contraseña y cierra todas las sesiones: sube la versión de sesión (invalida los JWT emitidos)
    /// y revoca los dispositivos de confianza (vuelve a pedir el 2FA).
    /// </summary>
    public static async Task AplicarNuevaPasswordAsync(AppDbContext db, Usuario usuario, string nuevaPassword, CancellationToken ct)
    {
        usuario.PasswordHash = BCrypt.Net.BCrypt.HashPassword(nuevaPassword, workFactor: 11);
        usuario.VersionSesion++;
        await db.DispositivosConfiables.Where(d => d.UsuarioId == usuario.Id).ExecuteDeleteAsync(ct);
    }

    private static string NombreRol(string rol) => rol switch
    {
        Roles.Vendedor => "Vendedor",
        Roles.Admin => "Administrador",
        Roles.Bodega => "Bodega",
        Roles.Compras => "Compras",
        Roles.Contador => "Contador",
        _ => rol
    };
}
