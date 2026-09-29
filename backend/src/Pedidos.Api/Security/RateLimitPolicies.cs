namespace Pedidos.Api.Security;

public static class RateLimitPolicies
{
    /// <summary>Limita intentos de login por IP para frenar fuerza bruta.</summary>
    public const string Login = "login";
}
