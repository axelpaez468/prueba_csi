using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Pedidos.Api.Data;
using Pedidos.Api.Dtos;

namespace Pedidos.Api.Controllers;

[ApiController]
[Route("api/productos")]
[Authorize]
public class ProductosController : ControllerBase
{
    private readonly AppDbContext _db;

    public ProductosController(AppDbContext db) => _db = db;

    [HttpGet]
    [ProducesResponseType<List<ProductoDto>>(StatusCodes.Status200OK)]
    public async Task<List<ProductoDto>> Listar(CancellationToken ct) =>
        await _db.Productos.AsNoTracking()
            .Where(p => p.Activo) // los productos dados de baja no se ofrecen en el catálogo
            .OrderBy(p => p.Nombre)
            .Select(p => new ProductoDto(p.Id, p.Codigo, p.Nombre, p.Precio, p.Stock))
            .ToListAsync(ct);
}
