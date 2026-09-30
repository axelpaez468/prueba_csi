using Microsoft.EntityFrameworkCore;
using Pedidos.Api.Data;
using Pedidos.Api.Domain;
using Pedidos.Api.Dtos;
using Pedidos.Api.Errors;
using Pedidos.Api.Notificaciones;
using Pedidos.Api.Security;

namespace Pedidos.Api.Services.Seguridad;

/// <summary>"Mi seguridad": contraseña, activación del 2FA, códigos de respaldo y accesos recientes.</summary>
public class CuentaService
{
    private readonly AppDbContext _db;
    private readonly Cifrador _cifrador;
    private readonly TotpService _totp;
    private readonly SegundoFactorService _segundoFactor;
    private readonly PoliticaPassword _politica;
    private readonly BitacoraService _bitacora;
    private readonly TokenService _tokens;
    private readonly IEnviadorCorreo _correo;

    public CuentaService(AppDbContext db, Cifrador cifrador, TotpService totp, SegundoFactorService segundoFactor,
        PoliticaPassword politica, BitacoraService bitacora, TokenService tokens, IEnviadorCorreo correo)
    {
        _db = db;
        _cifrador = cifrador;
        _totp = totp;
        _segundoFactor = segundoFactor;
        _politica = politica;
        _bitacora = bitacora;
        _tokens = tokens;
        _correo = correo;
    }

    private Task<Usuario> CargarAsync(int id, CancellationToken ct) => _db.Usuarios.FirstAsync(u => u.Id == id, ct);

    private static void ExigirPassword(Usuario u, string? password)
    {
        if (string.IsNullOrEmpty(password) || !AuthService.VerificarPassword(password, u.PasswordHash))
            throw new BusinessRuleException("La contraseña actual no es correcta.");
    }

    public async Task<EstadoSeguridadResponse> EstadoAsync(int usuarioId, CancellationToken ct)
    {
        var u = await _db.Usuarios.AsNoTracking().FirstAsync(x => x.Id == usuarioId, ct);
        return new EstadoSeguridadResponse(
            u.Email,
            u.DosFactor,
            await _segundoFactor.CodigosRespaldoRestantesAsync(u.Id, ct),
            u.DosFactorObligatorio);
    }

    // ---------- Contraseña ----------

    /// <returns>Una sesión nueva: la actual deja de valer porque cambiar la contraseña cierra todas las sesiones.</returns>
    public async Task<LoginResponse> CambiarPasswordAsync(int usuarioId, string? actual, string? nueva, ContextoCliente ctx,
        CancellationToken ct)
    {
        var u = await CargarAsync(usuarioId, ct);
        ExigirPassword(u, actual);
        if (actual == nueva)
            throw new BusinessRuleException("La nueva contraseña debe ser distinta de la actual.");
        var error = await _politica.ValidarAsync(nueva, u.Email, ct);
        if (error is not null)
            throw new BusinessRuleException(error);

        await RecuperacionService.AplicarNuevaPasswordAsync(_db, u, nueva!, ct);
        _bitacora.Registrar(EventosBitacora.PasswordCambiada, true, u.Email, ctx, u.Id);
        await _db.SaveChangesAsync(ct);

        _correo.Encolar(u.Email, "Tu contraseña fue cambiada",
            $"Hola {u.Username}:\n\nCambiaste la contraseña de tu cuenta desde {ctx.Dispositivo}. " +
            "Se cerraron las sesiones en otros dispositivos.\n\nSi no fuiste tú, contacta al administrador de inmediato.");
        return _tokens.Generar(u);
    }

    // ---------- 2FA con app autenticadora (Google Authenticator) ----------

    public async Task<IniciarTotpResponse> IniciarTotpAsync(int usuarioId, CancellationToken ct)
    {
        var u = await CargarAsync(usuarioId, ct);
        var (secreto, uri) = _segundoFactor.PrepararTotp(u); // queda pendiente hasta que el usuario lo confirme
        await _db.SaveChangesAsync(ct);
        return new IniciarTotpResponse(secreto, uri);
    }

    public async Task<CodigosRespaldoResponse> ConfirmarTotpAsync(int usuarioId, string? codigo, ContextoCliente ctx,
        CancellationToken ct)
    {
        var u = await CargarAsync(usuarioId, ct);
        if (u.TotpPendienteCifrado is null)
            throw new BusinessRuleException("Primero genera el código QR.");
        var codigos = await _segundoFactor.ActivarTotpPendienteAsync(u, codigo ?? "", ct)
                      ?? throw new BusinessRuleException("El código no es correcto. Revisa la hora de tu teléfono e intenta de nuevo.");

        _bitacora.Registrar(EventosBitacora.DosFactorActivado, true, u.Email, ctx, u.Id, MetodosDosFactor.Totp);
        await _db.SaveChangesAsync(ct);
        _correo.Encolar(u.Email, "Verificación en dos pasos activada",
            $"Hola {u.Username}:\n\nActivaste la verificación en dos pasos con Google Authenticator. " +
            "Guarda tus códigos de respaldo en un lugar seguro.");
        return new CodigosRespaldoResponse(codigos);
    }
    // ---------- Desactivar y códigos de respaldo ----------

    /// <returns>Una sesión nueva (desactivar cierra las demás sesiones, incluida la versión anterior de esta).</returns>
    public async Task<LoginResponse> DesactivarAsync(int usuarioId, string? password, ContextoCliente ctx, CancellationToken ct)
    {
        var u = await CargarAsync(usuarioId, ct);
        if (u.DosFactorObligatorio)
            throw new BusinessRuleException("La verificación en dos pasos es obligatoria para todos los usuarios.");
        ExigirPassword(u, password);

        u.DosFactor = MetodosDosFactor.Ninguno;
        u.TotpSecretoCifrado = u.TotpPendienteCifrado = null;
        u.TotpUltimoPaso = null;
        u.VersionSesion++; // desactivar la protección cierra las demás sesiones
        await _db.CodigosRespaldo.Where(c => c.UsuarioId == u.Id).ExecuteDeleteAsync(ct);
        await _db.DispositivosConfiables.Where(d => d.UsuarioId == u.Id).ExecuteDeleteAsync(ct);
        _bitacora.Registrar(EventosBitacora.DosFactorDesactivado, true, u.Email, ctx, u.Id);
        await _db.SaveChangesAsync(ct);

        _correo.Encolar(u.Email, "Verificación en dos pasos desactivada",
            $"Hola {u.Username}:\n\nSe desactivó la verificación en dos pasos de tu cuenta desde {ctx.Dispositivo}. " +
            "Si no fuiste tú, cambia tu contraseña de inmediato.");
        return _tokens.Generar(u);
    }

    public async Task<CodigosRespaldoResponse> RegenerarCodigosAsync(int usuarioId, string? password, ContextoCliente ctx,
        CancellationToken ct)
    {
        var u = await CargarAsync(usuarioId, ct);
        if (u.DosFactor == MetodosDosFactor.Ninguno)
            throw new BusinessRuleException("Activa primero la verificación en dos pasos.");
        ExigirPassword(u, password);
        var codigos = await _segundoFactor.RegenerarCodigosRespaldoAsync(u, ct);
        _bitacora.Registrar(EventosBitacora.CodigosRespaldoRegenerados, true, u.Email, ctx, u.Id);
        await _db.SaveChangesAsync(ct);
        return new CodigosRespaldoResponse(codigos);
    }

    // ---------- Bitácora ----------

    public async Task<List<RegistroAccesoResponse>> AccesosAsync(int? usuarioId, string? email, string? evento, int limite,
        CancellationToken ct)
    {
        var q = _db.BitacoraAccesos.AsNoTracking().AsQueryable();
        if (usuarioId is not null) q = q.Where(r => r.UsuarioId == usuarioId);
        if (!string.IsNullOrWhiteSpace(email)) q = q.Where(r => r.Email.Contains(email.Trim().ToLower()));
        if (!string.IsNullOrWhiteSpace(evento)) q = q.Where(r => r.Evento == evento);

        var filas = await q.OrderByDescending(r => r.Id).Take(Math.Clamp(limite, 1, 200)).ToListAsync(ct);
        return filas.Select(r => new RegistroAccesoResponse(r.Fecha, r.Email, r.Evento, r.Exito, r.Ip,
            ContextoCliente.DescribirDispositivo(r.UserAgent), r.Detalle)).ToList();
    }
}
