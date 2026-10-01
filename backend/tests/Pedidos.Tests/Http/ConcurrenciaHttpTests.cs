using System.Net;
using Microsoft.EntityFrameworkCore;
using Pedidos.Api.Domain;

namespace Pedidos.Tests.Http;

/// <summary>
/// Varias personas haciendo lo mismo al mismo tiempo, contra SQL Server real. En todos los casos: exactamente
/// lo que debe pasar una vez pasa una vez, los demás reciben un error claro (nunca un 500) y los datos quedan bien.
/// </summary>
[Collection(ApiColeccion.Nombre)]
public class ConcurrenciaHttpTests(ApiEnVivo api)
{
    private static void SinErroresDelServidor(IEnumerable<(HttpStatusCode Status, string Cuerpo)> respuestas)
    {
        var malas = respuestas.Where(r => (int)r.Status >= 500).ToList();
        Assert.True(malas.Count == 0, "Errores del servidor:\n" + string.Join("\n", malas.Select(m => $"{(int)m.Status} {m.Cuerpo}")));
    }

    private async Task<int> Producto(int stock)
    {
        using var bodega = await api.ComoAsync(Roles.Bodega);
        var codigo = "C-" + Guid.NewGuid().ToString("N")[..8].ToUpperInvariant();
        var id = (await bodega.PostJson("api/inventario/productos", new { codigo, nombre = $"Concurrencia {codigo}", precio = 100m, stockMinimo = 0 }).Creado()).Int("id");
        if (stock > 0)
            await bodega.PostJson("api/inventario/ajustes", new { productoId = id, tipo = "ENTRADA", cantidad = stock, costoUnitario = 40m, motivo = "Existencia para la prueba" }).Creado();
        return id;
    }

    private async Task<int> StockDe(int producto)
    {
        await using var db = api.Db();
        return await db.Productos.Where(p => p.Id == producto).Select(p => p.Stock).SingleAsync();
    }

    [ApiFact]
    public async Task VariosVendedores_PorLasUltimasUnidades_NuncaSeVendeDeMas()
    {
        var producto = await Producto(stock: 3);
        var vendedores = new List<HttpClient>();
        for (var i = 0; i < 6; i++) vendedores.Add(await api.ComoNuevoAsync(Roles.Vendedor));

        // 6 vendedores × 3 intentos = 18 ventas de 1 unidad por 3 unidades.
        var r = await HttpExt.Simultaneas(18, i =>
            vendedores[i % vendedores.Count].PostJson("api/pedidos", new { lineas = new[] { new { productoId = producto, cantidad = 1 } } }));

        SinErroresDelServidor(r);
        Assert.Equal(3, r.Count(x => x.Status == HttpStatusCode.Created));
        Assert.All(r.Where(x => x.Status != HttpStatusCode.Created), x => Assert.Equal(HttpStatusCode.BadRequest, x.Status));
        Assert.Equal(0, await StockDe(producto));

        await using var db = api.Db();
        var vendidas = await db.Set<PedidoDetalle>().Where(d => d.ProductoId == producto).SumAsync(d => d.Cantidad);
        Assert.Equal(3, vendidas);
        vendedores.ForEach(v => v.Dispose());
    }

    [ApiFact]
    public async Task DosEnBodega_AvanzanLaMismaVenta_SoloAvanzaUnaEtapa()
    {
        var producto = await Producto(stock: 1);
        using var vendedor = await api.ComoNuevoAsync(Roles.Vendedor);
        var numero = (await vendedor.PostJson("api/pedidos", new { lineas = new[] { new { productoId = producto, cantidad = 1 } } }).Creado()).Int("numero");
        await vendedor.PostJson($"api/pipeline/{numero}/avanzar").Ok();
        using var contador = await api.ComoAsync(Roles.Contador);
        await contador.PostJson($"api/pipeline/{numero}/avanzar").Ok(); // autorizada

        var bodegas = new List<HttpClient>();
        for (var i = 0; i < 4; i++) bodegas.Add(await api.ComoNuevoAsync(Roles.Bodega));
        var r = await HttpExt.Simultaneas(8, i => bodegas[i % bodegas.Count].PostJson($"api/pipeline/{numero}/avanzar"));

        SinErroresDelServidor(r);
        // Cada clic exitoso mueve una sola etapa; nunca se salta ni se duplica en el historial.
        var detalle = await vendedor.GetAsync($"api/pedidos/{numero}").Ok();
        var historial = detalle.GetProperty("historial").EnumerateArray().Select(h => h.Str("estado")).ToList();
        Assert.Equal(EstadosVenta.Orden.Take(historial.Count), historial);
        Assert.Equal(historial.Count - 3, r.Count(x => x.Status == HttpStatusCode.OK));
        Assert.Equal(historial[^1], detalle.Str("estado"));
        bodegas.ForEach(b => b.Dispose());
    }

    [ApiFact]
    public async Task RecibirLaMismaOrdenAlMismoTiempo_IngresaLaMercaderiaUnaSolaVez()
    {
        var producto = await Producto(stock: 0);
        using var compras = await api.ComoAsync(Roles.Compras);
        var proveedor = await compras.PostJson("api/compras/proveedores", new { nit = EntradasHttpTests.NitValido(), nombre = "Proveedor Simultáneo" }).Creado();
        var numero = (await compras.PostJson("api/compras/ordenes", new
        {
            proveedorId = proveedor.Int("id"), lineas = new[] { new { productoId = producto, cantidad = 7, costoUnitario = 20m } }
        }).Creado()).Int("numero");

        var bodegas = new List<HttpClient>();
        for (var i = 0; i < 4; i++) bodegas.Add(await api.ComoNuevoAsync(Roles.Bodega));
        var r = await HttpExt.Simultaneas(8, i => bodegas[i % bodegas.Count].PostJson($"api/compras/ordenes/{numero}/recibir", new { facturaProveedor = $"FAC-{i}" }));

        SinErroresDelServidor(r);
        Assert.Equal(1, r.Count(x => x.Status == HttpStatusCode.OK));
        Assert.Equal(7, await StockDe(producto));
        await using var db = api.Db();
        Assert.Equal(1, await db.Set<MovimientoInventario>().CountAsync(m => m.ProductoId == producto && m.Tipo == "COMPRA"));
        bodegas.ForEach(b => b.Dispose());
    }

    [ApiFact]
    public async Task AjustesDeSalidaSimultaneos_NuncaDejanExistenciaNegativa()
    {
        var producto = await Producto(stock: 5);
        var bodegas = new List<HttpClient>();
        for (var i = 0; i < 4; i++) bodegas.Add(await api.ComoNuevoAsync(Roles.Bodega));

        var r = await HttpExt.Simultaneas(12, i => bodegas[i % bodegas.Count].PostJson("api/inventario/ajustes",
            new { productoId = producto, tipo = "SALIDA", cantidad = 1, motivo = "Salida simultánea" }));

        SinErroresDelServidor(r);
        Assert.Equal(5, r.Count(x => x.Status == HttpStatusCode.Created));
        Assert.Equal(0, await StockDe(producto));
        bodegas.ForEach(b => b.Dispose());
    }

    [ApiFact]
    public async Task MismoClienteRegistradoDosVecesAlMismoTiempo_SoloQuedaUno()
    {
        var nit = EntradasHttpTests.NitValido();
        var vendedores = new List<HttpClient>();
        for (var i = 0; i < 4; i++) vendedores.Add(await api.ComoNuevoAsync(Roles.Vendedor));

        var r = await HttpExt.Simultaneas(8, i => vendedores[i % vendedores.Count].PostJson("api/clientes", new { nit, nombre = $"Cliente simultáneo {i}" }));

        SinErroresDelServidor(r);
        Assert.Equal(1, r.Count(x => x.Status == HttpStatusCode.Created));
        await using var db = api.Db();
        Assert.Equal(1, await db.Clientes.CountAsync(c => c.Nit == nit));
        vendedores.ForEach(v => v.Dispose());
    }

    [ApiFact]
    public async Task MismoCodigoDeProductoAlMismoTiempo_SoloQuedaUno()
    {
        var codigo = "D-" + Guid.NewGuid().ToString("N")[..8].ToUpperInvariant();
        var bodegas = new List<HttpClient>();
        for (var i = 0; i < 4; i++) bodegas.Add(await api.ComoNuevoAsync(Roles.Bodega));

        var r = await HttpExt.Simultaneas(8, i => bodegas[i % bodegas.Count].PostJson("api/inventario/productos",
            new { codigo, nombre = $"Duplicado {i}", precio = 10m, stockMinimo = 0 }));

        SinErroresDelServidor(r);
        Assert.Equal(1, r.Count(x => x.Status == HttpStatusCode.Created));
        bodegas.ForEach(b => b.Dispose());
    }

    [ApiFact]
    public async Task MismoProveedorAlMismoTiempo_SoloQuedaUno()
    {
        var nit = EntradasHttpTests.NitValido();
        var compras = new List<HttpClient>();
        for (var i = 0; i < 4; i++) compras.Add(await api.ComoNuevoAsync(Roles.Compras));

        var r = await HttpExt.Simultaneas(8, i => compras[i % compras.Count].PostJson("api/compras/proveedores", new { nit, nombre = $"Proveedor {i}" }));

        SinErroresDelServidor(r);
        Assert.Equal(1, r.Count(x => x.Status == HttpStatusCode.Created));
        compras.ForEach(c => c.Dispose());
    }

    [ApiFact]
    public async Task MismoCorreoDeUsuarioAlMismoTiempo_SoloQuedaUno()
    {
        var sufijo = Guid.NewGuid().ToString("N")[..6];
        var admins = new List<HttpClient>();
        for (var i = 0; i < 3; i++) admins.Add(await api.ComoNuevoAsync(Roles.Admin));

        var r = await HttpExt.Simultaneas(6, i => admins[i % admins.Count].PostJson("api/admin/usuarios", new
        {
            nombre = "Doble", apellido = "Registro", telefono = "55551111", email = $"doble.{sufijo}@pedidos.test",
            codigoCorporativo = $"DBL-{sufijo}-{i}".ToUpperInvariant()[..Math.Min(20, $"DBL-{sufijo}-{i}".Length)], rol = Roles.Vendedor
        }));

        SinErroresDelServidor(r);
        Assert.Equal(1, r.Count(x => x.Status == HttpStatusCode.Created));
        admins.ForEach(a => a.Dispose());
    }

    [ApiFact]
    public async Task ProbabilidadesGuardadasAlMismoTiempo_QuedanCompletasYEnOrden()
    {
        var admins = new List<HttpClient>();
        for (var i = 0; i < 3; i++) admins.Add(await api.ComoNuevoAsync(Roles.Admin));
        int[][] juegos = { new[] { 10, 25, 50, 75, 90, 100 }, new[] { 30, 40, 60, 80, 95, 100 }, new[] { 5, 10, 20, 40, 60, 100 } };

        var r = await HttpExt.Simultaneas(9, i => admins[i % 3].PutJson("api/reportes/pronostico/probabilidades",
            new { etapas = EstadosVenta.Orden.Select((e, k) => new { estado = e, probabilidad = juegos[i % 3][k] }) }));

        SinErroresDelServidor(r);
        await using var db = api.Db();
        var valores = await db.EtapasPipeline.ToDictionaryAsync(e => e.Estado, e => (int)e.Probabilidad);
        var guardado = EstadosVenta.Orden.Select(e => valores[e]).ToArray();
        Assert.Contains(juegos, j => j.SequenceEqual(guardado)); // uno de los tres juegos completo, nunca una mezcla

        await admins[0].PutJson("api/reportes/pronostico/probabilidades",
            new { etapas = EstadosVenta.Orden.Select((e, k) => new { estado = e, probabilidad = juegos[0][k] }) }).Ok();
        admins.ForEach(a => a.Dispose());
    }
}
