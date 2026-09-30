using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Options;
using Pedidos.Api.Data;
using Pedidos.Api.Domain;
using Pedidos.Api.Errors;
using Pedidos.Api.Notificaciones;
using Pedidos.Api.Security;

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
            _correo.Encolar(usuario.Email, "Restablece tu contraseña",
                $"Hola {usuario.Username}:\n\nRecibimos una solicitud para restablecer tu contraseña. " +
                $"Abre este enlace (vence en {VigenciaEnlace.TotalMinutes:0} minutos y funciona una sola vez):\n\n{enlace}\n\n" +
                $"Solicitud desde: {ctx.Dispositivo}, IP {ctx.Ip ?? "desconocida"}.\n" +
                "Si no fuiste tú, ignora este correo: tu contraseña no cambiará.");
        }

        await _db.SaveChangesAsync(ct);
    }

    /// <summary>Correo de bienvenida para un usuario creado por el administrador: define su contraseña con el enlace.</summary>
    public async Task EnviarInvitacionAsync(Usuario usuario, ContextoCliente ctx, CancellationToken ct)
    {
        var enlace = await CrearEnlaceAsync(usuario.Id, VigenciaInvitacion, ct);
        await _db.SaveChangesAsync(ct);
        _correo.Encolar(usuario.Email, "Bienvenido al Sistema de Pedidos",
            $"Hola {usuario.Nombre}:\n\nSe creó tu cuenta en el Sistema de Pedidos.\n\n" +
            $"  Correo de acceso: {usuario.Email}\n  Código corporativo: {usuario.CodigoCorporativo}\n  Rol: {usuario.Rol}\n\n" +
            $"Para activarla, crea tu contraseña con este enlace (vence en {VigenciaInvitacion.TotalHours:0} horas y funciona una sola vez):\n\n{enlace}\n\n" +
            (usuario.DosFactorObligatorio
                ? "Por tu rol, en tu primer inicio de sesión configurarás la verificación en dos pasos con Google Authenticator " +
                  "(descárgala gratis en tu teléfono).\n"
                : "") +
            "Si no esperabas este correo, ignóralo.");
    }

    /// <summary>
    /// Solo un enlace vigente por usuario: crear uno invalida los anteriores. En la BD se guarda solo la huella
    /// del token, así que una filtración de la BD no sirve para usar el enlace.
    /// </summary>
    private async Task<string> CrearEnlaceAsync(int usuarioId, TimeSpan vigencia, CancellationToken ct)
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
        return $"{_frontend.UrlPublica.TrimEnd('/')}/?restablecer={token}";
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

        registro.UsadoEn = Ahora;
        await AplicarNuevaPasswordAsync(_db, usuario, nuevaPassword, ct);
        _bitacora.Registrar(EventosBitacora.PasswordRestablecida, true, usuario.Email, ctx, usuario.Id);
        await _db.SaveChangesAsync(ct);

        _correo.Encolar(usuario.Email, "Tu contraseña fue cambiada",
            $"Hola {usuario.Username}:\n\nLa contraseña de tu cuenta se restableció el {Ahora:dd/MM/yyyy HH:mm} UTC. " +
            "Se cerraron las sesiones abiertas en otros dispositivos.\n\nSi no fuiste tú, contacta al administrador de inmediato.");
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
}
