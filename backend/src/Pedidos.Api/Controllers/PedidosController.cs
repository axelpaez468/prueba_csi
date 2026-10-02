using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.RateLimiting;
using Pedidos.Api.Domain;
using Pedidos.Api.Dtos;
using Pedidos.Api.Errors;
using Pedidos.Api.Security;
using Pedidos.Api.Services;

namespace Pedidos.Api.Controllers;

/// <summary>Ventas (pedidos) y sus facturas. Solo VENDEDOR vende; ADMIN y CONTADOR consultan todas.</summary>
[ApiController]
[Route("api/pedidos")]
[Authorize(Roles = Roles.ConsultaVentas)]
public class PedidosController : ControllerBase
{
    private readonly PedidoService _pedidos;
    private readonly TimeProvider _time;

    public PedidosController(PedidoService pedidos, TimeProvider time)
    {
        _pedidos = pedidos;
        _time = time;
    }

    private bool VeTodas => User.IsInRole(Roles.Admin) || User.IsInRole(Roles.Contador);

    [HttpPost]
    [Authorize(Roles = Roles.Vendedor)]
    [EnableRateLimiting(RateLimitPolicies.CrearPedido)]
    [ProducesResponseType<PedidoResponse>(StatusCodes.Status201Created)]
    [ProducesResponseType<ErrorResponse>(StatusCodes.Status400BadRequest)]
    public async Task<IActionResult> Crear(CrearPedidoRequest request, CancellationToken ct)
    {
        var pedido = await _pedidos.CrearAsync(User.GetUsuarioId(), request, ct);
        return CreatedAtAction(nameof(Obtener), new { id = pedido.Numero }, pedido);
    }

    /// <summary>Ventas del rango (por defecto, el mes en curso). El vendedor ve solo las suyas.</summary>
    [HttpGet]
    public Task<List<VentaResumenResponse>> Listar([FromQuery] DateOnly? desde, [FromQuery] DateOnly? hasta, CancellationToken ct)
    {
        var (d, h) = RangoPorDefecto.Resolver(desde, hasta, _time);
        return _pedidos.ListarAsync(User.GetUsuarioId(), VeTodas, d, h, ct);
    }

    [HttpGet("{id:int}")]
    [ProducesResponseType<PedidoResponse>(StatusCodes.Status200OK)]
    [ProducesResponseType<ErrorResponse>(StatusCodes.Status404NotFound)]
    public async Task<IActionResult> Obtener(int id, CancellationToken ct)
    {
        var pedido = await _pedidos.ObtenerAsync(id, User.GetUsuarioId(), VeTodas, ct);
        return pedido is null
            ? NotFound(new ErrorResponse("Pedido no encontrado."))
            : Ok(pedido);
    }
}
