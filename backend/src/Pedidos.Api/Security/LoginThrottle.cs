using Microsoft.Extensions.Caching.Memory;

namespace Pedidos.Api.Security;

/// <summary>
/// Bloqueo temporal por cuenta tras varios intentos fallidos. Complementa el límite por IP:
/// frena la fuerza bruta distribuida (muchas IPs contra el mismo usuario).
/// Cuenta también los intentos contra usuarios inexistentes, así que no revela cuáles existen.
/// El bloqueo es corto a propósito: uno largo permitiría a un atacante dejar sin acceso a un usuario legítimo.
/// </summary>
public class LoginThrottle
{
    public const int FallosPermitidos = 5;
    public static readonly TimeSpan DuracionBloqueo = TimeSpan.FromMinutes(5);
    private static readonly TimeSpan VentanaFallos = TimeSpan.FromMinutes(15);

    private readonly IMemoryCache _cache;
    private readonly TimeProvider _time;

    public LoginThrottle(IMemoryCache cache, TimeProvider time)
    {
        _cache = cache;
        _time = time;
    }

    private sealed class Estado
    {
        public int Fallos;
        public DateTimeOffset? BloqueadoHasta;
    }

    private static string Clave(string username) => "login-fallos:" + username.Trim().ToLowerInvariant();

    /// <returns>Tiempo que falta para desbloquear la cuenta, o null si no está bloqueada.</returns>
    public TimeSpan? TiempoBloqueo(string username)
    {
        if (!_cache.TryGetValue(Clave(username), out Estado? estado) || estado is null)
            return null;
        lock (estado)
        {
            var ahora = _time.GetUtcNow();
            return estado.BloqueadoHasta > ahora ? estado.BloqueadoHasta - ahora : null;
        }
    }

    public void RegistrarFallo(string username)
    {
        var estado = _cache.GetOrCreate(Clave(username), entrada =>
        {
            entrada.SetSize(1).SetSlidingExpiration(VentanaFallos);
            return new Estado();
        })!;

        lock (estado)
        {
            estado.Fallos++;
            if (estado.Fallos >= FallosPermitidos)
            {
                estado.BloqueadoHasta = _time.GetUtcNow() + DuracionBloqueo;
                estado.Fallos = 0;
            }
        }
    }

    public void RegistrarExito(string username) => _cache.Remove(Clave(username));
}
