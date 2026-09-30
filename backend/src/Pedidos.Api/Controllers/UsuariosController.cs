using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.RateLimiting;
using Pedidos.Api.Domain;
using Pedidos.Api.Dtos;
using Pedidos.Api.Errors;
using Pedidos.Api.Security;
using Pedidos.Api.Services.Seguridad;
using Pedidos.Api.Services.Usuarios;

namespace Pedidos.Api.Controllers;

/// <summary>Administración de usuarios. Solo ADMIN: un vendedor recibe 403.</summary>
[ApiController]
[Route("api/admin/usuarios")]
[Authorize(Roles = Roles.Admin)]
public class UsuariosController : ControllerBase
{
    private readonly UsuarioService _usuarios;

    public UsuariosController(UsuarioService usuarios) => _usuarios = usuarios;

    private int AdminId => User.GetUsuarioId();
    private ContextoCliente Cliente => ContextoCliente.Desde(HttpContext);

    [HttpGet]
    public Task<List<UsuarioResponse>> Listar([FromQuery] string? buscar, CancellationToken ct) =>
        _usuarios.ListarAsync(buscar, ct);

    [HttpGet("{id:int}")]
    [ProducesResponseType<UsuarioResponse>(StatusCodes.Status200OK)]
    [ProducesResponseType<ErrorResponse>(StatusCodes.Status404NotFound)]
    public async Task<IActionResult> Obtener(int id, CancellationToken ct) =>
        await _usuarios.ObtenerAsync(id, ct) is { } u ? Ok(u) : NotFound(new ErrorResponse("Usuario no encontrado."));

    /// <summary>Crea el usuario y le envía por correo la invitación para definir su contraseña.</summary>
    [HttpPost]
    [EnableRateLimiting(RateLimitPolicies.SegundoFactor)]
    [ProducesResponseType<UsuarioResponse>(StatusCodes.Status201Created)]
    [ProducesResponseType<ErrorResponse>(StatusCodes.Status400BadRequest)]
    public async Task<IActionResult> Crear(GuardarUsuarioRequest request, CancellationToken ct)
    {
        var u = await _usuarios.CrearAsync(request, AdminId, Cliente, ct);
        return CreatedAtAction(nameof(Obtener), new { id = u.Id }, u);
    }

    [HttpPut("{id:int}")]
    public Task<UsuarioResponse> Editar(int id, GuardarUsuarioRequest request, CancellationToken ct) =>
        _usuarios.EditarAsync(id, request, AdminId, Cliente, ct);

    [HttpPost("{id:int}/activar")]
    public Task<UsuarioResponse> Activar(int id, CancellationToken ct) =>
        _usuarios.CambiarEstadoAsync(id, true, AdminId, Cliente, ct);

    [HttpPost("{id:int}/desactivar")]
    public Task<UsuarioResponse> Desactivar(int id, CancellationToken ct) =>
        _usuarios.CambiarEstadoAsync(id, false, AdminId, Cliente, ct);

    [HttpPost("{id:int}/invitacion")]
    [EnableRateLimiting(RateLimitPolicies.SegundoFactor)]
    public async Task<MensajeResponse> ReenviarInvitacion(int id, CancellationToken ct)
    {
        await _usuarios.ReenviarInvitacionAsync(id, AdminId, Cliente, ct);
        return new MensajeResponse("Se envió la invitación al correo del usuario.");
    }

    /// <summary>Solo si no tiene pedidos; en ese caso hay que desactivarlo.</summary>
    [HttpDelete("{id:int}")]
    [ProducesResponseType(StatusCodes.Status204NoContent)]
    [ProducesResponseType<ErrorResponse>(StatusCodes.Status400BadRequest)]
    public async Task<IActionResult> Eliminar(int id, CancellationToken ct)
    {
        await _usuarios.EliminarAsync(id, AdminId, Cliente, ct);
        return NoContent();
    }
}
