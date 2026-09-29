using System.Threading.RateLimiting;

namespace Pedidos.Api.Security;

public static class RateLimitPolicies
{
    /// <summary>Limita intentos de login por IP para frenar fuerza bruta.</summary>
    public const string Login = "login";

    /// <summary>Limita la creación de pedidos por usuario (evita saturar la BD con transacciones).</summary>
    public const string CrearPedido = "crear-pedido";

    /// <summary>Límite global por IP para cualquier endpoint (primera barrera ante floods).</summary>
    public static RateLimitPartition<string> Global(HttpContext http) =>
        RateLimitPartition.GetFixedWindowLimiter(ClienteIp(http), _ => new FixedWindowRateLimiterOptions
        {
            PermitLimit = 300,
            Window = TimeSpan.FromMinutes(1),
            QueueLimit = 0
        });

    public static RateLimitPartition<string> PorIpLogin(HttpContext http) =>
        RateLimitPartition.GetFixedWindowLimiter(ClienteIp(http), _ => new FixedWindowRateLimiterOptions
        {
            PermitLimit = 10,
            Window = TimeSpan.FromMinutes(1),
            QueueLimit = 0
        });

    /// <summary>Token bucket por usuario: permite ráfagas cortas pero no un ritmo sostenido alto.</summary>
    public static RateLimitPartition<string> PorUsuarioPedidos(HttpContext http) =>
        RateLimitPartition.GetTokenBucketLimiter(
            http.User.FindFirst(JwtClaims.UserId)?.Value ?? "ip:" + ClienteIp(http),
            _ => new TokenBucketRateLimiterOptions
            {
                TokenLimit = 20,
                TokensPerPeriod = 20,
                ReplenishmentPeriod = TimeSpan.FromMinutes(1),
                QueueLimit = 0
            });

    // Si la API se publica detrás de un proxy, se debe configurar ForwardedHeaders con la IP del proxy
    // como confiable; de lo contrario todas las peticiones compartirían la IP del proxy.
    private static string ClienteIp(HttpContext http) => http.Connection.RemoteIpAddress?.ToString() ?? "desconocida";
}
