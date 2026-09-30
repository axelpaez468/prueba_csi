using Microsoft.EntityFrameworkCore;
using Pedidos.Api.Data;
using Pedidos.Api.Domain;
using Pedidos.Api.Errors;
using Pedidos.Api.Notificaciones;
using Pedidos.Api.Security;

namespace Pedidos.Api.Services.Seguridad;

/// <summary>Verificación de códigos del segundo factor: TOTP, SMS y códigos de respaldo.</summary>
public class SegundoFactorService
{
    public const int CantidadCodigosRespaldo = 10;
    public static readonly TimeSpan VigenciaCodigoSms = TimeSpan.FromMinutes(5);
    public static readonly TimeSpan EsperaReenvioSms = TimeSpan.FromSeconds(30);
    public const int IntentosPorCodigoSms = 5;

    private readonly AppDbContext _db;
    private readonly Cifrador _cifrador;
    private readonly TotpService _totp;
    private readonly IEnviadorSms _sms;
    private readonly TimeProvider _time;

    public SegundoFactorService(AppDbContext db, Cifrador cifrador, TotpService totp, IEnviadorSms sms, TimeProvider time)
    {
        _db = db;
        _cifrador = cifrador;
        _totp = totp;
        _sms = sms;
        _time = time;
    }

    private DateTime Ahora => _time.GetUtcNow().UtcDateTime;

    public static string EnmascararTelefono(string? telefono) =>
        string.IsNullOrEmpty(telefono) || telefono.Length < 4
            ? "•••"
            : $"{telefono[..Math.Min(4, telefono.Length - 4)]} •••• {telefono[^4..]}";

    // ---------- SMS ----------

    /// <summary>Genera un código de 6 dígitos, invalida los anteriores del mismo propósito y lo envía.</summary>
    public async Task EnviarCodigoSmsAsync(Usuario usuario, string telefono, string proposito, CancellationToken ct)
    {
        var anterior = await _db.CodigosVerificacion
            .Where(c => c.UsuarioId == usuario.Id && c.Proposito == proposito && c.UsadoEn == null)
            .OrderByDescending(c => c.CreadoEn)
            .FirstOrDefaultAsync(ct);
        if (anterior is not null && Ahora - anterior.CreadoEn < EsperaReenvioSms)
            throw new BusinessRuleException(
                $"Espera {EsperaReenvioSms.TotalSeconds:0} segundos antes de solicitar otro código.");

        await _db.CodigosVerificacion
            .Where(c => c.UsuarioId == usuario.Id && c.Proposito == proposito && c.UsadoEn == null)
            .ExecuteUpdateAsync(s => s.SetProperty(c => c.UsadoEn, Ahora), ct);

        var codigo = Aleatorio.CodigoNumerico();
        _db.CodigosVerificacion.Add(new CodigoVerificacion
        {
            UsuarioId = usuario.Id,
            Proposito = proposito,
            CodigoHash = _cifrador.Huella($"{usuario.Id}:{proposito}:{codigo}"),
            ExpiraEn = Ahora + VigenciaCodigoSms,
            CreadoEn = Ahora
        });
        await _db.SaveChangesAsync(ct);

        _sms.Encolar(telefono,
            $"Sistema de Pedidos: tu código de verificación es {codigo}. Vence en {VigenciaCodigoSms.TotalMinutes:0} minutos. " +
            "No lo compartas con nadie.");
    }

    public async Task<bool> VerificarCodigoSmsAsync(Usuario usuario, string proposito, string codigo, CancellationToken ct)
    {
        var vigente = await _db.CodigosVerificacion
            .Where(c => c.UsuarioId == usuario.Id && c.Proposito == proposito && c.UsadoEn == null && c.ExpiraEn > Ahora)
            .OrderByDescending(c => c.CreadoEn)
            .FirstOrDefaultAsync(ct);
        if (vigente is null || vigente.Intentos >= IntentosPorCodigoSms)
            return false;

        if (!_cifrador.CoincideHuella($"{usuario.Id}:{proposito}:{codigo.Trim()}", vigente.CodigoHash))
        {
            vigente.Intentos++;
            await _db.SaveChangesAsync(ct);
            return false;
        }

        vigente.UsadoEn = Ahora;
        return true;
    }

    // ---------- TOTP ----------

    public bool VerificarTotp(Usuario usuario, string secretoCifrado, string codigo)
    {
        if (!_totp.Verificar(_cifrador.Descifrar(secretoCifrado), codigo, usuario.TotpUltimoPaso, out var paso))
            return false;
        usuario.TotpUltimoPaso = paso;
        return true;
    }

    // ---------- Códigos de respaldo ----------

    public static bool PareceCodigoRespaldo(string codigo) => codigo.Trim().Length == 11 && codigo.Trim()[5] == '-';

    public async Task<List<string>> RegenerarCodigosRespaldoAsync(Usuario usuario, CancellationToken ct)
    {
        await _db.CodigosRespaldo.Where(c => c.UsuarioId == usuario.Id).ExecuteDeleteAsync(ct);
        var codigos = Enumerable.Range(0, CantidadCodigosRespaldo).Select(_ => Aleatorio.CodigoRespaldo()).ToList();
        _db.CodigosRespaldo.AddRange(codigos.Select(c => new CodigoRespaldo
        {
            UsuarioId = usuario.Id,
            CodigoHash = _cifrador.Huella($"{usuario.Id}:respaldo:{c}")
        }));
        return codigos;
    }

    public async Task<bool> UsarCodigoRespaldoAsync(Usuario usuario, string codigo, CancellationToken ct)
    {
        var huella = _cifrador.Huella($"{usuario.Id}:respaldo:{codigo.Trim().ToUpperInvariant()}");
        var guardado = await _db.CodigosRespaldo
            .FirstOrDefaultAsync(c => c.UsuarioId == usuario.Id && c.CodigoHash == huella && c.UsadoEn == null, ct);
        if (guardado is null) return false;
        guardado.UsadoEn = Ahora;
        return true;
    }

    public Task<int> CodigosRespaldoRestantesAsync(int usuarioId, CancellationToken ct) =>
        _db.CodigosRespaldo.CountAsync(c => c.UsuarioId == usuarioId && c.UsadoEn == null, ct);
}
