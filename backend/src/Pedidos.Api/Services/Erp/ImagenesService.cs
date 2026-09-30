using Microsoft.EntityFrameworkCore;
using Pedidos.Api.Data;
using Pedidos.Api.Domain;
using Pedidos.Api.Errors;

namespace Pedidos.Api.Services.Erp;

/// <summary>
/// Galería de fotos del producto (hasta 5). El formato se valida por la firma de los bytes (JPEG, PNG o WebP):
/// un archivo con otra cosa dentro se rechaza aunque diga ".jpg".
/// </summary>
public class ImagenesService
{
    private readonly AppDbContext _db;
    private readonly TimeProvider _time;

    public ImagenesService(AppDbContext db, TimeProvider time)
    {
        _db = db;
        _time = time;
    }

    /// <summary>Ids de las fotos de cada producto, en orden (la primera es la principal).</summary>
    public static async Task<Dictionary<int, List<int>>> IdsPorProductoAsync(AppDbContext db, IEnumerable<int> productos,
        CancellationToken ct)
    {
        var ids = productos.Distinct().ToList();
        var filas = await db.ProductoImagenes.AsNoTracking()
            .Where(i => ids.Contains(i.ProductoId))
            .OrderBy(i => i.ProductoId).ThenBy(i => i.Orden).ThenBy(i => i.Id)
            .Select(i => new { i.ProductoId, i.Id })
            .ToListAsync(ct);
        return filas.GroupBy(f => f.ProductoId).ToDictionary(g => g.Key, g => g.Select(f => f.Id).ToList());
    }

    public async Task<List<int>> SubirAsync(int productoId, byte[] datos, CancellationToken ct)
    {
        if (!await _db.Productos.AnyAsync(p => p.Id == productoId, ct))
            throw new NoEncontradoException("Producto no encontrado.");
        if (datos.Length == 0)
            throw new BusinessRuleException("El archivo está vacío.");
        if (datos.Length > ProductoImagen.TamanoMaximo)
            throw new BusinessRuleException($"La imagen pesa {datos.Length / 1024} KB; el máximo es {ProductoImagen.TamanoMaximo / 1024 / 1024} MB.");
        var tipo = TipoDeImagen(datos)
                   ?? throw new BusinessRuleException("Solo se aceptan imágenes JPG, PNG o WebP.");

        var existentes = await _db.ProductoImagenes.Where(i => i.ProductoId == productoId).Select(i => i.Orden).ToListAsync(ct);
        if (existentes.Count >= ProductoImagen.MaximoPorProducto)
            throw new BusinessRuleException($"El producto ya tiene {ProductoImagen.MaximoPorProducto} fotos. Elimina una para subir otra.");

        _db.ProductoImagenes.Add(new ProductoImagen
        {
            ProductoId = productoId,
            Orden = existentes.Count == 0 ? 0 : existentes.Max() + 1,
            ContentType = tipo,
            Datos = datos,
            Tamano = datos.Length,
            CreadoEn = _time.GetUtcNow().UtcDateTime
        });
        await _db.SaveChangesAsync(ct);
        return await IdsAsync(productoId, ct);
    }

    public async Task<List<int>> EliminarAsync(int productoId, int imagenId, CancellationToken ct)
    {
        var borradas = await _db.ProductoImagenes.Where(i => i.Id == imagenId && i.ProductoId == productoId).ExecuteDeleteAsync(ct);
        if (borradas == 0)
            throw new NoEncontradoException("Imagen no encontrada.");
        await RenumerarAsync(productoId, primera: null, ct);
        return await IdsAsync(productoId, ct);
    }

    /// <summary>La pasa al primer lugar (la que se muestra en el catálogo); las demás conservan su orden.</summary>
    public async Task<List<int>> HacerPrincipalAsync(int productoId, int imagenId, CancellationToken ct)
    {
        if (!await _db.ProductoImagenes.AnyAsync(i => i.Id == imagenId && i.ProductoId == productoId, ct))
            throw new NoEncontradoException("Imagen no encontrada.");
        await RenumerarAsync(productoId, imagenId, ct);
        return await IdsAsync(productoId, ct);
    }

    public async Task<(byte[] Datos, string ContentType)?> ObtenerAsync(int productoId, int imagenId, CancellationToken ct)
    {
        var img = await _db.ProductoImagenes.AsNoTracking()
            .Where(i => i.Id == imagenId && i.ProductoId == productoId)
            .Select(i => new { i.Datos, i.ContentType })
            .FirstOrDefaultAsync(ct);
        return img is null ? null : (img.Datos, img.ContentType);
    }

    private async Task<List<int>> IdsAsync(int productoId, CancellationToken ct) =>
        (await IdsPorProductoAsync(_db, new[] { productoId }, ct)).GetValueOrDefault(productoId) ?? new List<int>();

    /// <summary>Deja los órdenes 0..n-1 sin huecos; si se indica, esa imagen queda primera.</summary>
    private async Task RenumerarAsync(int productoId, int? primera, CancellationToken ct)
    {
        var ids = await _db.ProductoImagenes.Where(i => i.ProductoId == productoId)
            .OrderBy(i => i.Orden).ThenBy(i => i.Id).Select(i => i.Id).ToListAsync(ct);
        if (primera is { } p)
        {
            ids.Remove(p);
            ids.Insert(0, p);
        }
        for (var orden = 0; orden < ids.Count; orden++)
        {
            var id = ids[orden];
            var o = orden;
            await _db.ProductoImagenes.Where(i => i.Id == id).ExecuteUpdateAsync(s => s.SetProperty(i => i.Orden, o), ct);
        }
    }

    /// <summary>Firma de los primeros bytes: JPEG (FF D8 FF), PNG (89 50 4E 47 0D 0A 1A 0A) o WebP (RIFF....WEBP).</summary>
    public static string? TipoDeImagen(ReadOnlySpan<byte> b)
    {
        if (b.Length >= 3 && b[0] == 0xFF && b[1] == 0xD8 && b[2] == 0xFF) return "image/jpeg";
        if (b.Length >= 8 && b[..8].SequenceEqual(new byte[] { 0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A })) return "image/png";
        if (b.Length >= 12 && b[..4].SequenceEqual("RIFF"u8) && b[8..12].SequenceEqual("WEBP"u8)) return "image/webp";
        return null;
    }
}
