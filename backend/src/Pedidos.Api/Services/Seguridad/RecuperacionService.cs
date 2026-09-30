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
        _bitacora.Registrar(EventosBitacora.RecuperacionSolicitada, usuario is not null, email, ctx, usuario?.Id);

        if (usuario is not null)
        {
            // Solo un enlace vigente a la vez: pedir uno nuevo invalida los anteriores.
            await _db.TokensRecuperacion
                .Where(t => t.UsuarioId == usuario.Id && t.UsadoEn == null)
                .ExecuteUpdateAsync(s => s.SetProperty(t => t.UsadoEn, Ahora), ct);

            var token = Aleatorio.Token();
            _db.TokensRecuperacion.Add(new TokenRecuperacion
            {
                UsuarioId = usuario.Id,
                TokenHash = _cifrador.Huella(token), // en la BD solo la huella: una filtración no sirve para usar el enlace
                CreadoEn = Ahora,
                ExpiraEn = Ahora + VigenciaEnlace
            });

            var enlace = $"{_frontend.UrlPublica.TrimEnd('/')}/?restablecer={token}";
            _correo.Encolar(usuario.Email, "Restablece tu contraseña",
                $"Hola {usuario.Username}:\n\nRecibimos una solicitud para restablecer tu contraseña. " +
                $"Abre este enlace (vence en {VigenciaEnlace.TotalMinutes:0} minutos y funciona una sola vez):\n\n{enlace}\n\n" +
                $"Solicitud desde: {ctx.Dispositivo}, IP {ctx.Ip ?? "desconocida"}.\n" +
                "Si no fuiste tú, ignora este correo: tu contraseña no cambiará.");
        }

        await _db.SaveChangesAsync(ct);
    }

    public async Task RestablecerAsync(string token, string nuevaPassword, ContextoCliente ctx, CancellationToken ct)
    {
        var huella = _cifrador.Huella(token);
        var registro = await _db.TokensRecuperacion.FirstOrDefaultAsync(t => t.TokenHash == huella, ct);
        if (registro is null || registro.UsadoEn is not null || registro.ExpiraEn <= Ahora)
            throw new BusinessRuleException("El enlace no es válido o ya expiró. Solicita uno nuevo.");

        var usuario = await _db.Usuarios.FirstAsync(u => u.Id == registro.UsuarioId, ct);
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
