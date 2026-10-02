using System.Security.Cryptography;
using System.Text;
using Microsoft.Extensions.Options;

namespace Pedidos.Api.Security;

public class SeguridadOptions
{
    public const string Section = "Seguridad";

    /// <summary>
    /// Clave maestra (Base64, 32 bytes) de la que se derivan las claves de cifrado y de HMAC.
    /// Llega por variable de entorno (Seguridad__ClaveMaestra); nunca va en el repositorio.
    /// </summary>
    public string ClaveMaestra { get; set; } = string.Empty;

    public void Validar()
    {
        byte[] clave;
        try { clave = Convert.FromBase64String(ClaveMaestra); }
        catch (FormatException) { clave = Array.Empty<byte>(); }
        if (clave.Length != 32)
            throw new InvalidOperationException(
                "Seguridad__ClaveMaestra debe ser una clave de 32 bytes en Base64 (p. ej. openssl rand -base64 32).");
    }
}

/// <summary>
/// Cifrado de secretos en reposo (AES-256-GCM) y huellas de tokens/códigos (HMAC-SHA256).
/// Se derivan dos claves distintas de la clave maestra con HKDF, para que un uso no comprometa al otro.
/// </summary>
public class Cifrador
{
    private readonly byte[] _claveCifrado;
    private readonly byte[] _claveHmac;

    public Cifrador(IOptions<SeguridadOptions> options)
    {
        var maestra = Convert.FromBase64String(options.Value.ClaveMaestra);
        _claveCifrado = HKDF.DeriveKey(HashAlgorithmName.SHA256, maestra, 32, info: "pedidos-cifrado"u8.ToArray());
        _claveHmac = HKDF.DeriveKey(HashAlgorithmName.SHA256, maestra, 32, info: "pedidos-hmac"u8.ToArray());
    }

    /// <returns>Base64 de nonce(12) + tag(16) + texto cifrado.</returns>
    public string Cifrar(string texto)
    {
        var plano = Encoding.UTF8.GetBytes(texto);
        var salida = new byte[12 + 16 + plano.Length];
        var nonce = salida.AsSpan(0, 12);
        RandomNumberGenerator.Fill(nonce);
        using var aes = new AesGcm(_claveCifrado, 16);
        aes.Encrypt(nonce, plano, salida.AsSpan(28), salida.AsSpan(12, 16));
        return Convert.ToBase64String(salida);
    }

    public string Descifrar(string cifradoBase64)
    {
        var datos = Convert.FromBase64String(cifradoBase64);
        var plano = new byte[datos.Length - 28];
        using var aes = new AesGcm(_claveCifrado, 16);
        aes.Decrypt(datos.AsSpan(0, 12), datos.AsSpan(28), datos.AsSpan(12, 16), plano);
        return Encoding.UTF8.GetString(plano);
    }

    /// <summary>
    /// Huella para guardar tokens y códigos: si se filtra la BD, no sirven para iniciar sesión.
    /// Con HMAC (y no un hash simple) un código de 6 dígitos no se puede adivinar sin la clave del servidor.
    /// </summary>
    public string Huella(string valor) =>
        Convert.ToHexString(HMACSHA256.HashData(_claveHmac, Encoding.UTF8.GetBytes(valor)));

    public bool CoincideHuella(string valor, string huellaGuardada) =>
        CryptographicOperations.FixedTimeEquals(
            Encoding.ASCII.GetBytes(Huella(valor)), Encoding.ASCII.GetBytes(huellaGuardada));
}

public static class Aleatorio
{
    private const string AlfabetoRespaldo = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"; // sin 0/O ni 1/I

    /// <summary>Token opaco de 256 bits, apto para URLs.</summary>
    public static string Token() =>
        Convert.ToBase64String(RandomNumberGenerator.GetBytes(32)).TrimEnd('=').Replace('+', '-').Replace('/', '_');

    public static string CodigoNumerico(int digitos = 6) =>
        RandomNumberGenerator.GetInt32(0, (int)Math.Pow(10, digitos)).ToString().PadLeft(digitos, '0');

    /// <summary>Código de respaldo con formato XXXXX-XXXXX (unos 50 bits de entropía).</summary>
    public static string CodigoRespaldo()
    {
        Span<char> c = stackalloc char[11];
        for (var i = 0; i < 11; i++)
            c[i] = i == 5 ? '-' : AlfabetoRespaldo[RandomNumberGenerator.GetInt32(AlfabetoRespaldo.Length)];
        return new string(c);
    }
}
