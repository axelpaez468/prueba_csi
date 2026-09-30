using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Pedidos.Api.Data;
using Pedidos.Api.Dtos;
using Pedidos.Api.Errors;

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
            .Select(p => new ProductoDto(p.Id, p.Codigo, p.Nombre, p.Precio, p.Stock, p.Marca, p.Categoria))
            .ToListAsync(ct);

    /// <summary>Ficha del producto: descripción, garantía y especificaciones técnicas.</summary>
    [HttpGet("{id:int}")]
    [ProducesResponseType<ProductoDetalleDto>(StatusCodes.Status200OK)]
    [ProducesResponseType<ErrorResponse>(StatusCodes.Status404NotFound)]
    public async Task<IActionResult> Obtener(int id, CancellationToken ct)
    {
        var p = await _db.Productos.AsNoTracking().FirstOrDefaultAsync(x => x.Id == id && x.Activo, ct);
        return p is null
            ? NotFound(new ErrorResponse("Producto no encontrado."))
            : Ok(new ProductoDetalleDto(p.Id, p.Codigo, p.Nombre, p.Precio, p.Stock, p.Marca, p.Categoria, p.Descripcion,
                p.GarantiaMeses, p.Especificaciones.Select(e => new EspecificacionDto(e.Nombre, e.Valor)).ToList()));
    }
}
