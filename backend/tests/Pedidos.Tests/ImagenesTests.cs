using Microsoft.EntityFrameworkCore;
using Pedidos.Api.Domain;
using Pedidos.Api.Dtos;
using Pedidos.Api.Errors;
using Pedidos.Api.Services.Erp;
using Pedidos.Tests.Infra;

namespace Pedidos.Tests;

public class ImagenesTests : ErpTestBase
{
    private ImagenesService Imagenes() => new(Db.CrearContexto(), TimeProvider.System);

    /// <summary>Bytes con la firma de un JPEG (lo que se valida) seguidos de relleno.</summary>
    private static byte[] Jpeg(int tamano = 100) => new byte[] { 0xFF, 0xD8, 0xFF, 0xE0 }.Concat(new byte[tamano]).ToArray();

    [Fact]
    public async Task Subir_JpegPngYWebp_SeAceptan_YLaPrimeraEsLaPrincipal()
    {
        var png = new byte[] { 0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 1, 2 };
        var webp = "RIFF\0\0\0\0WEBPVP8 "u8.ToArray();

        await Imagenes().SubirAsync(1, Jpeg(), default);
        await Imagenes().SubirAsync(1, png, default);
        var ids = await Imagenes().SubirAsync(1, webp, default);

        Assert.Equal(3, ids.Count);
        var (_, tipo) = (await Imagenes().ObtenerAsync(1, ids[1], default))!.Value;
        Assert.Equal("image/png", tipo);
        Assert.Equal(ids[0], (await Inventario().ListarAsync("P001", false, default)).Single().Imagenes[0]);
    }

    [Fact]
    public async Task Subir_UnArchivoQueNoEsImagen_SeRechaza_AunqueDigaJpg()
    {
        var ex = await Assert.ThrowsAsync<BusinessRuleException>(() =>
            Imagenes().SubirAsync(1, "<script>alert(1)</script>"u8.ToArray(), default));
        Assert.Contains("JPG, PNG o WebP", ex.Message);
    }

    [Fact]
    public async Task Subir_MasDeCinco_OMuyPesada_SeRechaza()
    {
        for (var i = 0; i < ProductoImagen.MaximoPorProducto; i++)
            await Imagenes().SubirAsync(1, Jpeg(), default);

        await Assert.ThrowsAsync<BusinessRuleException>(() => Imagenes().SubirAsync(1, Jpeg(), default));
        await Assert.ThrowsAsync<BusinessRuleException>(() => Imagenes().SubirAsync(2, Jpeg(ProductoImagen.TamanoMaximo), default));
    }

    [Fact]
    public async Task HacerPrincipal_YEliminar_MantienenElOrdenSinHuecos()
    {
        await Imagenes().SubirAsync(1, Jpeg(), default);
        await Imagenes().SubirAsync(1, Jpeg(), default);
        var ids = await Imagenes().SubirAsync(1, Jpeg(), default); // [a, b, c]

        var principal = await Imagenes().HacerPrincipalAsync(1, ids[2], default);
        Assert.Equal(new[] { ids[2], ids[0], ids[1] }, principal);

        var despues = await Imagenes().EliminarAsync(1, ids[2], default);
        Assert.Equal(new[] { ids[0], ids[1] }, despues);
        await using var db = Db.CrearContexto();
        Assert.Equal(new[] { 0, 1 }, db.ProductoImagenes.Where(i => i.ProductoId == 1).OrderBy(i => i.Orden).Select(i => i.Orden));
    }

    [Fact]
    public async Task Imagen_DeOtroProducto_NoSeEntrega_NiSeBorra()
    {
        var ids = await Imagenes().SubirAsync(1, Jpeg(), default);

        Assert.Null(await Imagenes().ObtenerAsync(2, ids[0], default));
        await Assert.ThrowsAsync<NoEncontradoException>(() => Imagenes().EliminarAsync(2, ids[0], default));
    }

    [Fact]
    public async Task EliminarProducto_SinHistoria_LoBorraConSusFotos()
    {
        var nuevo = await Inventario().CrearAsync(new GuardarProductoRequest("P-040", "Base para laptop", 180m, 0, null), default);
        await Imagenes().SubirAsync(nuevo.Id, Jpeg(), default);

        await Inventario().EliminarAsync(nuevo.Id, default);

        await using var db = Db.CrearContexto();
        Assert.False(await db.Productos.AnyAsync(p => p.Id == nuevo.Id));
        Assert.False(await db.ProductoImagenes.AnyAsync(i => i.ProductoId == nuevo.Id));
    }

    [Fact]
    public async Task EliminarProducto_ConVentas_SeRechaza_YPideDesactivarlo()
    {
        await Vender(1, 1);

        var ex = await Assert.ThrowsAsync<BusinessRuleException>(() => Inventario().EliminarAsync(1, default));
        Assert.Contains("Desactívalo", ex.Message);
    }

    [Fact]
    public void TipoDeImagen_ReconoceLasFirmas()
    {
        Assert.Equal("image/jpeg", ImagenesService.TipoDeImagen(Jpeg()));
        Assert.Null(ImagenesService.TipoDeImagen(new byte[] { 0x47, 0x49, 0x46, 0x38 })); // GIF: no se acepta
        Assert.Null(ImagenesService.TipoDeImagen(Array.Empty<byte>()));
    }
}
