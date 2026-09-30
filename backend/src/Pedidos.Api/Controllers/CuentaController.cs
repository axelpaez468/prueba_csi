using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.RateLimiting;
using Pedidos.Api.Domain;
using Pedidos.Api.Dtos;
using Pedidos.Api.Security;
using Pedidos.Api.Services.Seguridad;

namespace Pedidos.Api.Controllers;

/// <summary>Seguridad de la cuenta del usuario autenticado.</summary>
[ApiController]
[Route("api/cuenta")]
[Authorize]
[EnableRateLimiting(RateLimitPolicies.SegundoFactor)]
public class CuentaController : ControllerBase
{
    private readonly CuentaService _cuenta;

    public CuentaController(CuentaService cuenta) => _cuenta = cuenta;

    private int UsuarioId => User.GetUsuarioId();
    private ContextoCliente Cliente => ContextoCliente.Desde(HttpContext);

    [HttpGet("seguridad")]
    public Task<EstadoSeguridadResponse> Estado(CancellationToken ct) => _cuenta.EstadoAsync(UsuarioId, ct);

    [HttpPost("password")]
    public Task<LoginResponse> CambiarPassword(CambiarPasswordRequest r, CancellationToken ct) =>
        _cuenta.CambiarPasswordAsync(UsuarioId, r.Actual, r.Nueva, Cliente, ct);

    [HttpPost("2fa/totp")]
    public Task<IniciarTotpResponse> IniciarTotp(CancellationToken ct) => _cuenta.IniciarTotpAsync(UsuarioId, ct);

    [HttpPost("2fa/totp/confirmar")]
    public Task<CodigosRespaldoResponse> ConfirmarTotp(ConfirmarCodigoRequest r, CancellationToken ct) =>
        _cuenta.ConfirmarTotpAsync(UsuarioId, r.Codigo, Cliente, ct);

    [HttpPost("2fa/sms")]
    public async Task<MensajeResponse> IniciarSms(IniciarSmsRequest r, CancellationToken ct)
    {
        await _cuenta.IniciarSmsAsync(UsuarioId, r.Telefono, ct);
        return new MensajeResponse("Te enviamos un código por SMS.");
    }

    [HttpPost("2fa/sms/confirmar")]
    public Task<CodigosRespaldoResponse> ConfirmarSms(ConfirmarCodigoRequest r, CancellationToken ct) =>
        _cuenta.ConfirmarSmsAsync(UsuarioId, r.Codigo, Cliente, ct);

    [HttpPost("2fa/desactivar")]
    public Task<LoginResponse> Desactivar(ConfirmarPasswordRequest r, CancellationToken ct) =>
        _cuenta.DesactivarAsync(UsuarioId, r.Password, Cliente, ct);

    [HttpPost("2fa/codigos-respaldo")]
    public Task<CodigosRespaldoResponse> RegenerarCodigos(ConfirmarPasswordRequest r, CancellationToken ct) =>
        _cuenta.RegenerarCodigosAsync(UsuarioId, r.Password, Cliente, ct);

    [HttpGet("accesos")]
    public Task<List<RegistroAccesoResponse>> MisAccesos(CancellationToken ct) =>
        _cuenta.AccesosAsync(UsuarioId, null, null, 20, ct);
}

/// <summary>Bitácora completa de accesos (auditoría), solo para administradores.</summary>
[ApiController]
[Route("api/admin")]
[Authorize(Roles = Roles.Admin)]
public class AdminController : ControllerBase
{
    private readonly CuentaService _cuenta;

    public AdminController(CuentaService cuenta) => _cuenta = cuenta;

    [HttpGet("bitacora")]
    public Task<List<RegistroAccesoResponse>> Bitacora([FromQuery] string? email, [FromQuery] string? evento,
        CancellationToken ct) =>
        _cuenta.AccesosAsync(null, email, evento, 100, ct);
}
