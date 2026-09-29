using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Pedidos.Api.Domain;
using Pedidos.Api.Dtos;
using Pedidos.Api.Errors;
using Pedidos.Api.Security;
using Pedidos.Api.Services;

namespace Pedidos.Api.Controllers;

[ApiController]
[Route("api/pedidos")]
[Authorize]
public class PedidosController : ControllerBase
{
    private readonly PedidoService _pedidos;

    public PedidosController(PedidoService pedidos) => _pedidos = pedidos;

    [HttpPost]
    [Authorize(Roles = Roles.Vendedor)]
    [ProducesResponseType<PedidoResponse>(StatusCodes.Status201Created)]
    [ProducesResponseType<ErrorResponse>(StatusCodes.Status400BadRequest)]
    public async Task<IActionResult> Crear(CrearPedidoRequest request, CancellationToken ct)
    {
        var pedido = await _pedidos.CrearAsync(User.GetUsuarioId(), request, ct);
        return CreatedAtAction(nameof(Obtener), new { id = pedido.Numero }, pedido);
    }

    [HttpGet("{id:int}")]
    [ProducesResponseType<PedidoResponse>(StatusCodes.Status200OK)]
    [ProducesResponseType<ErrorResponse>(StatusCodes.Status404NotFound)]
    public async Task<IActionResult> Obtener(int id, CancellationToken ct)
    {
        var pedido = await _pedidos.ObtenerAsync(id, User.GetUsuarioId(), User.IsInRole(Roles.Admin), ct);
        return pedido is null
            ? NotFound(new ErrorResponse("Pedido no encontrado."))
            : Ok(pedido);
    }
}
