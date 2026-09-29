using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.RateLimiting;
using Pedidos.Api.Dtos;
using Pedidos.Api.Errors;
using Pedidos.Api.Security;
using Pedidos.Api.Services;

namespace Pedidos.Api.Controllers;

[ApiController]
[Route("api/auth")]
public class AuthController : ControllerBase
{
    private readonly AuthService _auth;
    private readonly ILogger<AuthController> _logger;

    public AuthController(AuthService auth, ILogger<AuthController> logger)
    {
        _auth = auth;
        _logger = logger;
    }

    [HttpPost("login")]
    [AllowAnonymous]
    [EnableRateLimiting(RateLimitPolicies.Login)]
    [ProducesResponseType<LoginResponse>(StatusCodes.Status200OK)]
    [ProducesResponseType<ErrorResponse>(StatusCodes.Status400BadRequest)]
    [ProducesResponseType<ErrorResponse>(StatusCodes.Status401Unauthorized)]
    [ProducesResponseType<ErrorResponse>(StatusCodes.Status429TooManyRequests)]
    public async Task<IActionResult> Login(LoginRequest request, CancellationToken ct)
    {
        if (string.IsNullOrWhiteSpace(request.Username) || string.IsNullOrEmpty(request.Password))
            return BadRequest(new ErrorResponse("Usuario y contraseña son obligatorios."));

        if (request.Username.Length > InputLimits.UsernameMax || request.Password.Length > InputLimits.PasswordMax)
            return BadRequest(new ErrorResponse("Usuario o contraseña demasiado largos."));

        var username = request.Username.Trim();
        var resultado = await _auth.LoginAsync(username, request.Password, ct);
        var ip = HttpContext.Connection.RemoteIpAddress?.ToString();
        // Sin caracteres de control: un usuario con saltos de línea no puede falsificar entradas del log.
        var usernameLog = new string(username.Where(c => !char.IsControl(c)).ToArray());

        if (resultado.BloqueadoPor is { } espera)
        {
            _logger.LogWarning("Login rechazado por cuenta bloqueada: {Username} desde {Ip}", usernameLog, ip);
            Response.Headers.RetryAfter = ((int)Math.Ceiling(espera.TotalSeconds)).ToString();
            return StatusCode(StatusCodes.Status429TooManyRequests,
                new ErrorResponse($"Demasiados intentos fallidos. Intente de nuevo en {Math.Ceiling(espera.TotalMinutes)} minuto(s)."));
        }

        if (resultado.Sesion is null)
        {
            // Registro de seguridad: permite detectar ataques. Nunca se registra la contraseña.
            _logger.LogWarning("Login fallido: {Username} desde {Ip}", usernameLog, ip);
            return Unauthorized(new ErrorResponse("Usuario o contraseña incorrectos."));
        }

        return Ok(resultado.Sesion);
    }
}
