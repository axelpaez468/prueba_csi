using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Pedidos.Api.Data;
using Pedidos.Api.Dtos;
using Pedidos.Api.Errors;
using Pedidos.Api.Services.Erp;

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
    public async Task<List<ProductoDto>> Listar(CancellationToken ct)
    {
        var productos = await _db.Productos.AsNoTracking()
            .Where(p => p.Activo) // los productos dados de baja no se ofrecen en el catálogo
            .OrderBy(p => p.Nombre)
            .Select(p => new ProductoDto(p.Id, p.Codigo, p.Nombre, p.Precio, p.Stock, p.Marca, p.Categoria, null))
            .ToListAsync(ct);
        var imagenes = await ImagenesService.IdsPorProductoAsync(_db, productos.Select(p => p.Id), ct);
        return productos
            .Select(p => p with { ImagenId = imagenes.TryGetValue(p.Id, out var ids) ? ids[0] : null })
            .ToList();
    }

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
                p.GarantiaMeses, p.Especificaciones.Select(e => new EspecificacionDto(e.Nombre, e.Valor)).ToList(),
                (await ImagenesService.IdsPorProductoAsync(_db, new[] { id }, ct)).GetValueOrDefault(id) ?? new List<int>()));
    }

    /// <summary>
    /// Foto del producto. Es pública (el navegador la carga como imagen, sin token) porque una foto de catálogo
    /// no es información sensible. El id cambia con cada subida, así que la respuesta se puede guardar en caché.
    /// </summary>
    [HttpGet("{id:int}/imagenes/{imagenId:int}")]
    [AllowAnonymous]
    [ProducesResponseType(StatusCodes.Status200OK)]
    [ProducesResponseType<ErrorResponse>(StatusCodes.Status404NotFound)]
    public async Task<IActionResult> Imagen(int id, int imagenId, [FromServices] ImagenesService imagenes, CancellationToken ct)
    {
        var img = await imagenes.ObtenerAsync(id, imagenId, ct);
        if (img is null) return NotFound(new ErrorResponse("Imagen no encontrada."));
        Response.Headers.CacheControl = "public, max-age=604800, immutable";
        // Las fotos se muestran desde el frontend (otro origen): se permite su uso entre orígenes.
        Response.Headers["Cross-Origin-Resource-Policy"] = "cross-origin";
        return File(img.Value.Datos, img.Value.ContentType);
    }
}
