using System.Text;

namespace Pedidos.Api.Security;

public class JwtOptions
{
    public const string Section = "Jwt";

    /// <summary>HS256 requiere una clave de al menos 256 bits.</summary>
    public const int MinKeyBytes = 32;

    /// <summary>Se inyecta por variable de entorno (Jwt__Key); nunca va en appsettings.</summary>
    public string Key { get; set; } = string.Empty;
    public string Issuer { get; set; } = "Pedidos.Api";
    public string Audience { get; set; } = "Pedidos.Frontend";
    public int ExpirationMinutes { get; set; } = 60;

    public void Validar()
    {
        if (Encoding.UTF8.GetByteCount(Key) < MinKeyBytes)
            throw new InvalidOperationException(
                $"La variable de entorno Jwt__Key no está definida o tiene menos de {MinKeyBytes} bytes.");
        if (ExpirationMinutes <= 0)
            throw new InvalidOperationException("Jwt__ExpirationMinutes debe ser mayor que cero.");
    }
}
