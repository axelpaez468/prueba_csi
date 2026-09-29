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

    public AuthController(AuthService auth) => _auth = auth;

    [HttpPost("login")]
    [AllowAnonymous]
    [EnableRateLimiting(RateLimitPolicies.Login)]
    [ProducesResponseType<LoginResponse>(StatusCodes.Status200OK)]
    [ProducesResponseType<ErrorResponse>(StatusCodes.Status400BadRequest)]
    [ProducesResponseType<ErrorResponse>(StatusCodes.Status401Unauthorized)]
    public async Task<IActionResult> Login(LoginRequest request, CancellationToken ct)
    {
        if (string.IsNullOrWhiteSpace(request.Username) || string.IsNullOrEmpty(request.Password))
            return BadRequest(new ErrorResponse("Usuario y contraseña son obligatorios."));

        var resultado = await _auth.LoginAsync(request.Username.Trim(), request.Password, ct);

        // Mensaje genérico: no se indica si falló el usuario o la contraseña.
        return resultado is null
            ? Unauthorized(new ErrorResponse("Usuario o contraseña incorrectos."))
            : Ok(resultado);
    }
}
