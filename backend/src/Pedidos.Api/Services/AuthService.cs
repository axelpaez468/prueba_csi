using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Caching.Memory;
using Pedidos.Api.Data;
using Pedidos.Api.Domain;
using Pedidos.Api.Dtos;
using Pedidos.Api.Errors;
using Pedidos.Api.Notificaciones;
using Pedidos.Api.Security;
using Pedidos.Api.Services.Seguridad;

namespace Pedidos.Api.Services;

/// <summary>Resultado del primer paso del login.</summary>
public record LoginResultado(LoginResponse? Sesion, DesafioResponse? Desafio, TimeSpan? BloqueadoPor, bool Desactivada = false)
{
    public static LoginResultado Invalido => new(null, null, null);
}

public class AuthService
{
    public static readonly TimeSpan VigenciaDispositivoConfiable = TimeSpan.FromDays(30);
    public const int IntentosPorDesafio = 5;

    // Si el usuario no existe se verifica igual contra este hash, para que el tiempo de
    // respuesta no permita distinguir "usuario inexistente" de "contraseña incorrecta".
    private static readonly string HashFicticio = BCrypt.Net.BCrypt.HashPassword(Guid.NewGuid().ToString());

    private readonly AppDbContext _db;
    private readonly TokenService _tokens;
    private readonly LoginThrottle _throttle;
    private readonly BitacoraService _bitacora;
    private readonly SegundoFactorService _segundoFactor;
    private readonly Cifrador _cifrador;
    private readonly IEnviadorCorreo _correo;
    private readonly IMemoryCache _cache;
    private readonly TimeProvider _time;

    public AuthService(AppDbContext db, TokenService tokens, LoginThrottle throttle, BitacoraService bitacora,
        SegundoFactorService segundoFactor, Cifrador cifrador, IEnviadorCorreo correo, IMemoryCache cache,
        TimeProvider time)
    {
        _db = db;
        _tokens = tokens;
        _throttle = throttle;
        _bitacora = bitacora;
        _segundoFactor = segundoFactor;
        _cifrador = cifrador;
        _correo = correo;
        _cache = cache;
        _time = time;
    }

    private DateTime Ahora => _time.GetUtcNow().UtcDateTime;

    public static string NormalizarEmail(string email) => email.Trim().ToLowerInvariant();

    /// <summary>
    /// Verifica contra BCrypt. Un usuario invitado que aún no creó su contraseña no tiene un hash BCrypt:
    /// se verifica igual contra el hash ficticio (mismo tiempo de respuesta) y el resultado es siempre falso.
    /// </summary>
    public static bool VerificarPassword(string password, string? hash)
    {
        var esBcrypt = hash is not null && hash.StartsWith("$2");
        var resultado = BCrypt.Net.BCrypt.Verify(password, esBcrypt ? hash : HashFicticio);
        return esBcrypt && resultado;
    }

    // ---------- Paso 1: correo y contraseña ----------

    public async Task<LoginResultado> LoginAsync(string email, string password, string? tokenDispositivo,
        ContextoCliente ctx, CancellationToken ct)
    {
        email = NormalizarEmail(email);

        // Con la cuenta bloqueada ni siquiera se verifica la contraseña: así la fuerza bruta no avanza.
        var bloqueo = _throttle.TiempoBloqueo(email);
        if (bloqueo is not null)
        {
            _bitacora.Registrar(EventosBitacora.CuentaBloqueada, false, email, ctx);
            await _db.SaveChangesAsync(ct);
            return new LoginResultado(null, null, bloqueo);
        }

        // Consulta LINQ: EF Core la envía parametrizada, nunca concatenada.
        var usuario = await _db.Usuarios.FirstOrDefaultAsync(u => u.Email == email, ct);
        var passwordValida = VerificarPassword(password, usuario?.PasswordHash);
        if (usuario is null || !passwordValida)
        {
            _throttle.RegistrarFallo(email);
            _bitacora.Registrar(EventosBitacora.LoginFallido, false, email, ctx, usuario?.Id);
            await _db.SaveChangesAsync(ct);
            return LoginResultado.Invalido;
        }

        _throttle.RegistrarExito(email);

        // Solo se informa tras validar la contraseña: a quien no la conoce no se le revela que la cuenta existe.
        if (!usuario.Activo)
        {
            _bitacora.Registrar(EventosBitacora.CuentaDesactivada, false, email, ctx, usuario.Id);
            await _db.SaveChangesAsync(ct);
            return new LoginResultado(null, null, null, Desactivada: true);
        }

        if (usuario.DosFactor != MetodosDosFactor.Ninguno && !await DispositivoConfiableAsync(usuario, tokenDispositivo, ct))
        {
            string? destino = null;
            if (usuario.DosFactor == MetodosDosFactor.Sms)
            {
                await _segundoFactor.EnviarCodigoSmsAsync(usuario, usuario.Telefono!, PropositosCodigo.Login, ct,
                    reusarReciente: true);
                destino = SegundoFactorService.EnmascararTelefono(usuario.Telefono);
            }
            _bitacora.Registrar(EventosBitacora.SegundoFactorRequerido, true, email, ctx, usuario.Id, usuario.DosFactor);
            await _db.SaveChangesAsync(ct);
            return new LoginResultado(null, new DesafioResponse(_tokens.GenerarDesafio(usuario), usuario.DosFactor, destino), null);
        }

        return new LoginResultado(await CompletarLoginAsync(usuario, ctx, null, ct), null, null);
    }

    // ---------- Paso 2: segundo factor ----------

    public async Task<LoginResponse?> VerificarSegundoFactorAsync(string? desafio, string codigo, bool confiarDispositivo,
        ContextoCliente ctx, CancellationToken ct)
    {
        var (usuario, desafioId) = await ResolverDesafioAsync(desafio, ct);

        // Tope de intentos por desafío: al agotarse hay que volver a escribir la contraseña.
        var intentos = _cache.GetOrCreate($"desafio:{desafioId}", e =>
        {
            e.SetSize(1).SetAbsoluteExpiration(TokenService.DuracionDesafio);
            return new ContadorIntentos();
        })!;
        if (intentos.Usado || Interlocked.Increment(ref intentos.Valor) > IntentosPorDesafio)
            throw new BusinessRuleException("Demasiados intentos o código ya utilizado. Inicia sesión de nuevo.");

        bool valido;
        var usoRespaldo = SegundoFactorService.PareceCodigoRespaldo(codigo);
        if (usoRespaldo)
            valido = await _segundoFactor.UsarCodigoRespaldoAsync(usuario, codigo, ct);
        else if (usuario.DosFactor == MetodosDosFactor.Totp)
            valido = _segundoFactor.VerificarTotp(usuario, usuario.TotpSecretoCifrado!, codigo);
        else
            valido = await _segundoFactor.VerificarCodigoSmsAsync(usuario, PropositosCodigo.Login, codigo, ct);

        if (!valido)
        {
            _bitacora.Registrar(EventosBitacora.SegundoFactorFallido, false, usuario.Email, ctx, usuario.Id);
            await _db.SaveChangesAsync(ct);
            return null;
        }

        intentos.Usado = true; // un desafío completado no se puede reutilizar
        if (usoRespaldo)
            _bitacora.Registrar(EventosBitacora.CodigoRespaldoUsado, true, usuario.Email, ctx, usuario.Id);

        string? tokenDispositivo = null;
        if (confiarDispositivo)
        {
            tokenDispositivo = Aleatorio.Token();
            _db.DispositivosConfiables.Add(new DispositivoConfiable
            {
                UsuarioId = usuario.Id,
                TokenHash = _cifrador.Huella(tokenDispositivo),
                CreadoEn = Ahora,
                ExpiraEn = Ahora + VigenciaDispositivoConfiable
            });
        }

        return await CompletarLoginAsync(usuario, ctx, tokenDispositivo, ct);
    }

    public async Task<string> ReenviarCodigoSmsAsync(string? desafio, CancellationToken ct)
    {
        var (usuario, _) = await ResolverDesafioAsync(desafio, ct);
        if (usuario.DosFactor != MetodosDosFactor.Sms)
            throw new BusinessRuleException("Tu cuenta no usa verificación por SMS.");
        await _segundoFactor.EnviarCodigoSmsAsync(usuario, usuario.Telefono!, PropositosCodigo.Login, ct);
        return SegundoFactorService.EnmascararTelefono(usuario.Telefono);
    }

    // ---------- Auxiliares ----------

    private sealed class ContadorIntentos
    {
        public int Valor;
        public bool Usado;
    }

    private async Task<(Usuario, string)> ResolverDesafioAsync(string? desafio, CancellationToken ct)
    {
        var datos = _tokens.ValidarDesafio(desafio)
                    ?? throw new BusinessRuleException("La verificación expiró. Inicia sesión de nuevo.");
        var usuario = await _db.Usuarios.FirstOrDefaultAsync(u => u.Id == datos.UsuarioId, ct);
        // Si la contraseña o el 2FA cambiaron después de emitir el desafío, ya no es válido.
        if (usuario is null || !usuario.Activo || usuario.VersionSesion != datos.VersionSesion
            || usuario.DosFactor == MetodosDosFactor.Ninguno)
            throw new BusinessRuleException("La verificación expiró. Inicia sesión de nuevo.");
        return (usuario, datos.DesafioId);
    }

    private async Task<bool> DispositivoConfiableAsync(Usuario usuario, string? token, CancellationToken ct)
    {
        if (string.IsNullOrWhiteSpace(token) || token.Length > 100) return false;
        var huella = _cifrador.Huella(token);
        return await _db.DispositivosConfiables.AnyAsync(
            d => d.UsuarioId == usuario.Id && d.TokenHash == huella && d.ExpiraEn > Ahora, ct);
    }

    private async Task<LoginResponse> CompletarLoginAsync(Usuario usuario, ContextoCliente ctx, string? tokenDispositivo,
        CancellationToken ct)
    {
        _bitacora.Registrar(EventosBitacora.LoginExitoso, true, usuario.Email, ctx, usuario.Id);

        // Aviso de acceso desde un dispositivo nuevo (navegador/sistema no visto antes para este usuario).
        var huella = _cifrador.Huella($"{usuario.Id}|{ctx.UserAgent}");
        var conocido = await _db.DispositivosConocidos.FirstOrDefaultAsync(d => d.UsuarioId == usuario.Id && d.Huella == huella, ct);
        if (conocido is null)
        {
            _db.DispositivosConocidos.Add(new DispositivoConocido
            {
                UsuarioId = usuario.Id, Huella = huella, PrimerAcceso = Ahora, UltimoAcceso = Ahora
            });
            _bitacora.Registrar(EventosBitacora.DispositivoNuevo, true, usuario.Email, ctx, usuario.Id, ctx.Dispositivo);
            _correo.Encolar(usuario.Email, "Nuevo inicio de sesión en tu cuenta",
                $"Hola {usuario.Username}:\n\nSe inició sesión en tu cuenta desde un dispositivo nuevo.\n\n" +
                $"  Dispositivo: {ctx.Dispositivo}\n  IP: {ctx.Ip ?? "desconocida"}\n  Fecha: {Ahora:dd/MM/yyyy HH:mm} UTC\n\n" +
                "Si fuiste tú, no necesitas hacer nada. Si no reconoces este acceso, cambia tu contraseña de inmediato.");
        }
        else
        {
            conocido.UltimoAcceso = Ahora;
        }

        await _db.SaveChangesAsync(ct);
        return _tokens.Generar(usuario, tokenDispositivo);
    }
}
