using System.Security.Cryptography;
using System.Text;

namespace Pedidos.Api.Security;

public interface IVerificadorPasswordFiltrada
{
    /// <returns>true si la contraseña aparece en filtraciones públicas.</returns>
    Task<bool> EstaFiltradaAsync(string password, CancellationToken ct);
}

/// <summary>
/// Consulta gratuita a Have I Been Pwned (Pwned Passwords) con k-anonimato: solo se envían los primeros
/// 5 caracteres del SHA-1 de la contraseña, nunca la contraseña ni su hash completo.
/// Si el servicio no responde se permite continuar (fail-open) y se registra una advertencia:
/// no depender de un tercero para que los usuarios puedan cambiar su contraseña.
/// </summary>
public class HibpVerificador : IVerificadorPasswordFiltrada
{
    private readonly HttpClient _http;
    private readonly ILogger<HibpVerificador> _logger;

    public HibpVerificador(HttpClient http, ILogger<HibpVerificador> logger)
    {
        _http = http;
        _logger = logger;
    }

    public async Task<bool> EstaFiltradaAsync(string password, CancellationToken ct)
    {
        var sha1 = Convert.ToHexString(SHA1.HashData(Encoding.UTF8.GetBytes(password)));
        var prefijo = sha1[..5];
        var sufijo = sha1[5..];
        try
        {
            using var req = new HttpRequestMessage(HttpMethod.Get, $"range/{prefijo}");
            req.Headers.Add("Add-Padding", "true"); // respuestas de tamaño uniforme: no se infiere el prefijo por el tamaño
            using var res = await _http.SendAsync(req, ct);
            res.EnsureSuccessStatusCode();
            var cuerpo = await res.Content.ReadAsStringAsync(ct);
            return cuerpo.Split('\n').Any(linea =>
                linea.StartsWith(sufijo, StringComparison.OrdinalIgnoreCase)
                && !linea.TrimEnd().EndsWith(":0")); // las líneas de relleno tienen conteo 0
        }
        catch (Exception ex) when (ex is HttpRequestException or TaskCanceledException)
        {
            _logger.LogWarning("No se pudo consultar Pwned Passwords; se omite la verificación: {Error}", ex.Message);
            return false;
        }
    }
}

/// <summary>
/// Política alineada con NIST SP 800-63B: largo mínimo en lugar de reglas de composición,
/// y rechazo de contraseñas conocidas por filtraciones.
/// </summary>
public class PoliticaPassword
{
    public const int LargoMinimo = 12;

    private readonly IVerificadorPasswordFiltrada _filtradas;

    public PoliticaPassword(IVerificadorPasswordFiltrada filtradas) => _filtradas = filtradas;

    /// <returns>Mensaje de error para el usuario, o null si la contraseña es aceptable.</returns>
    public async Task<string?> ValidarAsync(string? password, string email, CancellationToken ct)
    {
        if (string.IsNullOrEmpty(password) || password.Length < LargoMinimo)
            return $"La contraseña debe tener al menos {LargoMinimo} caracteres.";
        if (password.Length > InputLimits.PasswordMax)
            return $"La contraseña no puede superar {InputLimits.PasswordMax} caracteres.";

        var usuario = email.Split('@')[0];
        if (usuario.Length >= 4 && password.Contains(usuario, StringComparison.OrdinalIgnoreCase))
            return "La contraseña no debe contener tu correo.";
        if (password.Distinct().Count() < 4)
            return "La contraseña es demasiado repetitiva.";

        if (await _filtradas.EstaFiltradaAsync(password, ct))
            return "Esta contraseña aparece en filtraciones de datos públicas. Elige otra.";

        return null;
    }
}
