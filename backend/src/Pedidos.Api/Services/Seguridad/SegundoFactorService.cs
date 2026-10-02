using Microsoft.EntityFrameworkCore;
using Pedidos.Api.Data;
using Pedidos.Api.Domain;
using Pedidos.Api.Security;

namespace Pedidos.Api.Services.Seguridad;

/// <summary>Segundo factor: códigos de la app autenticadora (TOTP) y códigos de respaldo.</summary>
public class SegundoFactorService
{
    public const int CantidadCodigosRespaldo = 10;

    private readonly AppDbContext _db;
    private readonly Cifrador _cifrador;
    private readonly TotpService _totp;
    private readonly TimeProvider _time;

    public SegundoFactorService(AppDbContext db, Cifrador cifrador, TotpService totp, TimeProvider time)
    {
        _db = db;
        _cifrador = cifrador;
        _totp = totp;
        _time = time;
    }

    // ---------- TOTP ----------

    /// <summary>Genera un secreto nuevo y lo deja pendiente (cifrado) hasta que el usuario confirme un código.</summary>
    public (string Secreto, string Uri) PrepararTotp(Usuario usuario)
    {
        var (secreto, uri) = _totp.Generar(usuario.Email);
        usuario.TotpPendienteCifrado = _cifrador.Cifrar(secreto);
        return (secreto, uri);
    }

    public bool VerificarTotp(Usuario usuario, string secretoCifrado, string codigo)
    {
        if (!_totp.Verificar(_cifrador.Descifrar(secretoCifrado), codigo, usuario.TotpUltimoPaso, out var paso))
            return false;
        usuario.TotpUltimoPaso = paso;
        return true;
    }

    /// <summary>Confirma el secreto pendiente con un código de la app y activa el 2FA. Devuelve los códigos de respaldo.</summary>
    public async Task<List<string>?> ActivarTotpPendienteAsync(Usuario usuario, string codigo, CancellationToken ct)
    {
        if (usuario.TotpPendienteCifrado is null) return null;
        usuario.TotpUltimoPaso = null;
        if (!VerificarTotp(usuario, usuario.TotpPendienteCifrado, codigo)) return null;

        usuario.TotpSecretoCifrado = usuario.TotpPendienteCifrado;
        usuario.TotpPendienteCifrado = null;
        usuario.DosFactor = MetodosDosFactor.Totp;
        return await RegenerarCodigosRespaldoAsync(usuario, ct);
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
        guardado.UsadoEn = _time.GetUtcNow().UtcDateTime;
        return true;
    }

    public Task<int> CodigosRespaldoRestantesAsync(int usuarioId, CancellationToken ct) =>
        _db.CodigosRespaldo.CountAsync(c => c.UsuarioId == usuarioId && c.UsadoEn == null, ct);
}
