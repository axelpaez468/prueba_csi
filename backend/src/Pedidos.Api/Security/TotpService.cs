using OtpNet;

namespace Pedidos.Api.Security;

/// <summary>
/// Códigos TOTP (RFC 6238), compatibles con Google Authenticator, Microsoft Authenticator, etc.
/// Estándar abierto: no depende de ningún servicio externo.
/// </summary>
public class TotpService
{
    public const string Emisor = "Sistema de Pedidos";

    /// <returns>Secreto en Base32 y la URI otpauth:// que se muestra como código QR.</returns>
    public (string Secreto, string Uri) Generar(string email)
    {
        var secreto = Base32Encoding.ToString(KeyGeneration.GenerateRandomKey(20));
        var uri = new OtpUri(OtpType.Totp, secreto, email, Emisor).ToString();
        return (secreto, uri);
    }

    /// <summary>
    /// Acepta el código del intervalo actual o del anterior/siguiente (desfase de reloj de ±30 s),
    /// y rechaza un paso ya usado: un código interceptado no se puede reutilizar.
    /// </summary>
    public bool Verificar(string secreto, string codigo, long? ultimoPasoUsado, out long paso)
    {
        paso = 0;
        codigo = codigo.Trim().Replace(" ", "");
        if (codigo.Length != 6 || !codigo.All(char.IsDigit))
            return false;

        var totp = new Totp(Base32Encoding.ToBytes(secreto));
        return totp.VerifyTotp(codigo, out paso, new VerificationWindow(previous: 1, future: 1))
               && (ultimoPasoUsado is null || paso > ultimoPasoUsado);
    }
}
