using Pedidos.Api.Data;
using Pedidos.Api.Domain;

namespace Pedidos.Api.Services.Seguridad;

/// <summary>Datos del cliente que hace la petición, para la bitácora y la detección de dispositivos nuevos.</summary>
public record ContextoCliente(string? Ip, string? UserAgent)
{
    public static ContextoCliente Desde(HttpContext http) => new(
        http.Connection.RemoteIpAddress?.ToString(),
        Limpiar(http.Request.Headers.UserAgent.ToString(), 300));

    /// <summary>Recorta y quita caracteres de control (evita inyectar líneas falsas en logs/reportes).</summary>
    public static string? Limpiar(string? valor, int largo)
    {
        if (string.IsNullOrWhiteSpace(valor)) return null;
        var limpio = new string(valor.Where(c => !char.IsControl(c)).ToArray());
        return limpio.Length > largo ? limpio[..largo] : limpio;
    }

    /// <summary>Descripción legible del navegador y sistema ("Chrome en Windows").</summary>
    public string Dispositivo => DescribirDispositivo(UserAgent);

    public static string DescribirDispositivo(string? ua)
    {
        if (string.IsNullOrEmpty(ua)) return "Dispositivo desconocido";
        var navegador = ua.Contains("Edg/") ? "Edge" : ua.Contains("Chrome/") ? "Chrome"
            : ua.Contains("Firefox/") ? "Firefox" : ua.Contains("Safari/") ? "Safari"
            : ua.Contains("curl/") ? "curl" : "Navegador";
        var so = ua.Contains("Windows") ? "Windows" : ua.Contains("Android") ? "Android"
            : ua.Contains("iPhone") || ua.Contains("iPad") ? "iOS" : ua.Contains("Mac OS") ? "macOS"
            : ua.Contains("Linux") ? "Linux" : "sistema desconocido";
        return $"{navegador} en {so}";
    }
}

/// <summary>Registro de auditoría de accesos y cambios de seguridad.</summary>
public class BitacoraService
{
    private readonly AppDbContext _db;
    private readonly TimeProvider _time;

    public BitacoraService(AppDbContext db, TimeProvider time)
    {
        _db = db;
        _time = time;
    }

    /// <summary>Agrega el registro al contexto; se persiste con el SaveChanges de la operación que lo origina.</summary>
    public void Registrar(string evento, bool exito, string email, ContextoCliente ctx, int? usuarioId = null,
        string? detalle = null)
    {
        _db.BitacoraAccesos.Add(new RegistroAcceso
        {
            UsuarioId = usuarioId,
            Email = ContextoCliente.Limpiar(email, 254) ?? "(vacío)",
            Evento = evento,
            Exito = exito,
            Ip = ContextoCliente.Limpiar(ctx.Ip, 45),
            UserAgent = ctx.UserAgent,
            Detalle = ContextoCliente.Limpiar(detalle, 300),
            Fecha = _time.GetUtcNow().UtcDateTime
        });
    }
}
