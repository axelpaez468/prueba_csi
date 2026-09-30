using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.RateLimiting;
using Pedidos.Api.Dtos;
using Pedidos.Api.Errors;
using Pedidos.Api.Security;
using Pedidos.Api.Services;
using Pedidos.Api.Services.Seguridad;

namespace Pedidos.Api.Controllers;

[ApiController]
[Route("api/auth")]
[AllowAnonymous]
public class AuthController : ControllerBase
{
    private readonly AuthService _auth;
    private readonly RecuperacionService _recuperacion;
    private readonly ILogger<AuthController> _logger;

    public AuthController(AuthService auth, RecuperacionService recuperacion, ILogger<AuthController> logger)
    {
        _auth = auth;
        _recuperacion = recuperacion;
        _logger = logger;
    }

    private ContextoCliente Cliente => ContextoCliente.Desde(HttpContext);

    private static bool EmailValido(string? email) =>
        !string.IsNullOrWhiteSpace(email) && email.Length <= 254 && email.Contains('@') && !email.Any(char.IsWhiteSpace);

    /// <summary>
    /// Paso 1. Devuelve la sesión (200 + token) o, si la cuenta tiene 2FA, un desafío
    /// (200 + requiereSegundoFactor: true) para completar con /login/verificar.
    /// </summary>
    [HttpPost("login")]
    [EnableRateLimiting(RateLimitPolicies.Login)]
    [ProducesResponseType<LoginResponse>(StatusCodes.Status200OK)]
    [ProducesResponseType<DesafioResponse>(StatusCodes.Status200OK)]
    [ProducesResponseType<ErrorResponse>(StatusCodes.Status401Unauthorized)]
    [ProducesResponseType<ErrorResponse>(StatusCodes.Status429TooManyRequests)]
    public async Task<IActionResult> Login(LoginRequest request, CancellationToken ct)
    {
        if (string.IsNullOrWhiteSpace(request.Email) || string.IsNullOrEmpty(request.Password))
            return BadRequest(new ErrorResponse("Correo y contraseña son obligatorios."));
        if (!EmailValido(request.Email) || request.Password.Length > InputLimits.PasswordMax)
            return BadRequest(new ErrorResponse("Correo o contraseña con formato no válido."));

        var ctx = Cliente;
        var resultado = await _auth.LoginAsync(request.Email, request.Password, request.TokenDispositivo, ctx, ct);

        if (resultado.BloqueadoPor is { } espera)
        {
            Response.Headers.RetryAfter = ((int)Math.Ceiling(espera.TotalSeconds)).ToString();
            return StatusCode(StatusCodes.Status429TooManyRequests,
                new ErrorResponse($"Demasiados intentos fallidos. Intenta de nuevo en {Math.Ceiling(espera.TotalMinutes)} minuto(s)."));
        }
        if (resultado.Desactivada)
            return StatusCode(StatusCodes.Status403Forbidden,
                new ErrorResponse("Tu cuenta está desactivada. Contacta al administrador."));
        if (resultado.Desafio is not null)
            return Ok(resultado.Desafio);
        if (resultado.Sesion is not null)
            return Ok(resultado.Sesion);

        // Registro de seguridad sin contraseña ni caracteres de control (ver ContextoCliente.Limpiar).
        _logger.LogWarning("Login fallido: {Email} desde {Ip}", ContextoCliente.Limpiar(request.Email, 254), ctx.Ip);
        return Unauthorized(new ErrorResponse("Correo o contraseña incorrectos."));
    }

    /// <summary>Paso 2: código de la app autenticadora, del SMS o de respaldo.</summary>
    [HttpPost("login/verificar")]
    [EnableRateLimiting(RateLimitPolicies.SegundoFactor)]
    [ProducesResponseType<LoginResponse>(StatusCodes.Status200OK)]
    [ProducesResponseType<ErrorResponse>(StatusCodes.Status401Unauthorized)]
    public async Task<IActionResult> Verificar(VerificarSegundoFactorRequest request, CancellationToken ct)
    {
        if (string.IsNullOrWhiteSpace(request.Codigo) || request.Codigo.Length > 20)
            return BadRequest(new ErrorResponse("Ingresa el código de verificación."));

        var sesion = await _auth.VerificarSegundoFactorAsync(request.Desafio, request.Codigo, request.ConfiarDispositivo, Cliente, ct);
        return sesion is null
            ? Unauthorized(new ErrorResponse("El código no es correcto o ya expiró."))
            : Ok(sesion);
    }

    [HttpPost("login/reenviar")]
    [EnableRateLimiting(RateLimitPolicies.SegundoFactor)]
    [ProducesResponseType<MensajeResponse>(StatusCodes.Status200OK)]
    public async Task<IActionResult> Reenviar(ReenviarCodigoRequest request, CancellationToken ct)
    {
        var destino = await _auth.ReenviarCodigoSmsAsync(request.Desafio, ct);
        return Ok(new MensajeResponse($"Enviamos un nuevo código a {destino}."));
    }

    /// <summary>Siempre responde lo mismo, exista o no el correo (no revela qué cuentas existen).</summary>
    [HttpPost("recuperar")]
    [EnableRateLimiting(RateLimitPolicies.Recuperacion)]
    [ProducesResponseType<MensajeResponse>(StatusCodes.Status202Accepted)]
    public async Task<IActionResult> Recuperar(RecuperarPasswordRequest request, CancellationToken ct)
    {
        if (!EmailValido(request.Email))
            return BadRequest(new ErrorResponse("Ingresa un correo válido."));

        await _recuperacion.SolicitarAsync(request.Email!, Cliente, ct);
        return Accepted(new MensajeResponse(
            "Si el correo está registrado, recibirás un enlace para restablecer tu contraseña en unos minutos."));
    }

    // Límite más holgado que "recuperar": el token es de 256 bits (no se puede adivinar) y el usuario
    // puede equivocarse al elegir una contraseña que cumpla la política.
    [HttpPost("restablecer")]
    [EnableRateLimiting(RateLimitPolicies.SegundoFactor)]
    [ProducesResponseType<MensajeResponse>(StatusCodes.Status200OK)]
    [ProducesResponseType<ErrorResponse>(StatusCodes.Status400BadRequest)]
    public async Task<IActionResult> Restablecer(RestablecerPasswordRequest request, CancellationToken ct)
    {
        if (string.IsNullOrWhiteSpace(request.Token) || request.Token.Length > 100)
            throw new BusinessRuleException("El enlace no es válido o ya expiró. Solicita uno nuevo.");

        await _recuperacion.RestablecerAsync(request.Token, request.NuevaPassword ?? "", Cliente, ct);
        return Ok(new MensajeResponse("Tu contraseña se actualizó. Ya puedes iniciar sesión."));
    }
}
