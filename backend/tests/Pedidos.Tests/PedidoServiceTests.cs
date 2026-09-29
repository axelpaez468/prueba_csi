using System.Text.Json;
using Pedidos.Api.Dtos;
using Pedidos.Api.Errors;
using Pedidos.Api.Security;
using Pedidos.Api.Services;
using Pedidos.Tests.Infra;

namespace Pedidos.Tests;

public class PedidoServiceTests : IDisposable
{
    private readonly TestDb _testDb = new();

    public void Dispose() => _testDb.Dispose();

    private async Task<PedidoResponse> Crear(int usuarioId, params LineaPedidoRequest[] lineas)
    {
        await using var db = _testDb.CrearContexto();
        return await new PedidoService(db, TimeProvider.System).CrearAsync(usuarioId, new CrearPedidoRequest(lineas.ToList()));
    }

    private static LineaPedidoRequest Linea(int productoId, int cantidad) => new(productoId, cantidad);

    // ---------- Regla 1: precio y total calculados en el servidor ----------

    [Fact]
    public async Task Crear_IgnoraPrecioYTotalEnviadosPorElCliente_YUsaElPrecioDeLaBaseDeDatos()
    {
        // El cliente intenta pagar 1 por cada artículo y declara un total de 2.
        const string json = """
            { "lineas": [ { "productoId": 1, "cantidad": 2, "precio": 1 },
                          { "productoId": 2, "cantidad": 1, "precioUnitario": 1 } ],
              "total": 2 }
            """;
        var request = JsonSerializer.Deserialize<CrearPedidoRequest>(json, new JsonSerializerOptions(JsonSerializerDefaults.Web))!;

        await using var db = _testDb.CrearContexto();
        var pedido = await new PedidoService(db, TimeProvider.System).CrearAsync(TestDb.VendedorId, request);

        Assert.Equal(150.00m, pedido.Lineas.Single(l => l.ProductoId == 1).PrecioUnitario);
        Assert.Equal(300.00m, pedido.Lineas.Single(l => l.ProductoId == 1).Subtotal);
        Assert.Equal(75.50m, pedido.Lineas.Single(l => l.ProductoId == 2).Subtotal);
        Assert.Equal(375.50m, pedido.Total);
    }

    [Fact]
    public async Task Crear_DescuentaStock_YDevuelveNumeroDePedido()
    {
        var pedido = await Crear(TestDb.VendedorId, Linea(1, 3), Linea(2, 2));

        Assert.True(pedido.Numero > 0);
        Assert.Equal(7, _testDb.StockDe(1));
        Assert.Equal(3, _testDb.StockDe(2));
    }

    // ---------- Reglas 2 y 3: stock y transacción ----------

    [Fact]
    public async Task Crear_ConStockInsuficiente_Falla_YNoDejaCambiosParciales()
    {
        // La línea del teclado sí tiene stock; el monitor no (hay 1, se piden 2).
        // Como todo es una transacción, el stock del teclado no debe quedar descontado.
        var ex = await Assert.ThrowsAsync<BusinessRuleException>(() =>
            Crear(TestDb.VendedorId, Linea(1, 4), Linea(3, 2)));

        Assert.Contains("Stock insuficiente", ex.Message);
        Assert.Equal(10, _testDb.StockDe(1));
        Assert.Equal(1, _testDb.StockDe(3));
        Assert.Equal(0, _testDb.CantidadPedidos());
    }

    [Fact]
    public async Task Crear_UltimaUnidad_SoloSePuedeVenderUnaVez()
    {
        await Crear(TestDb.VendedorId, Linea(3, 1));

        await Assert.ThrowsAsync<BusinessRuleException>(() => Crear(TestDb.OtroVendedorId, Linea(3, 1)));

        Assert.Equal(0, _testDb.StockDe(3));
        Assert.Equal(1, _testDb.CantidadPedidos());
    }

    // ---------- Regla 4: validaciones de entrada ----------

    [Theory]
    [InlineData(0)]
    [InlineData(-5)]
    public async Task Crear_ConCantidadMenorOIgualACero_Falla(int cantidad)
    {
        var ex = await Assert.ThrowsAsync<BusinessRuleException>(() => Crear(TestDb.VendedorId, Linea(1, cantidad)));

        Assert.Contains("mayor que cero", ex.Message);
        Assert.Equal(10, _testDb.StockDe(1));
    }

    [Fact]
    public async Task Crear_ConProductoInexistente_Falla()
    {
        var ex = await Assert.ThrowsAsync<BusinessRuleException>(() =>
            Crear(TestDb.VendedorId, Linea(1, 1), Linea(999, 1)));

        Assert.Contains("999", ex.Message);
        Assert.Equal(10, _testDb.StockDe(1));
    }

    [Fact]
    public async Task Crear_ConProductoDuplicado_Falla()
    {
        var ex = await Assert.ThrowsAsync<BusinessRuleException>(() =>
            Crear(TestDb.VendedorId, Linea(1, 1), Linea(1, 2)));

        Assert.Contains("más de una vez", ex.Message);
        Assert.Equal(10, _testDb.StockDe(1));
    }

    [Fact]
    public async Task Crear_SinLineas_Falla()
    {
        await Assert.ThrowsAsync<BusinessRuleException>(() => Crear(TestDb.VendedorId));
    }

    // ---------- Límites de tamaño (protección contra abuso de recursos) ----------

    [Fact]
    public async Task Crear_ConDemasiadasLineas_Falla()
    {
        var lineas = Enumerable.Range(1, InputLimits.LineasPorPedidoMax + 1).Select(id => Linea(id, 1)).ToArray();

        var ex = await Assert.ThrowsAsync<BusinessRuleException>(() => Crear(TestDb.VendedorId, lineas));

        Assert.Contains("máximo", ex.Message);
    }

    [Fact]
    public async Task Crear_ConCantidadDesproporcionada_Falla()
    {
        var ex = await Assert.ThrowsAsync<BusinessRuleException>(() =>
            Crear(TestDb.VendedorId, Linea(1, InputLimits.CantidadPorLineaMax + 1)));

        Assert.Contains("supera el máximo", ex.Message);
        Assert.Equal(10, _testDb.StockDe(1));
    }

    // ---------- Autorización a nivel de recurso ----------

    [Fact]
    public async Task Obtener_PedidoDeOtroVendedor_NoDevuelveDatos()
    {
        var pedido = await Crear(TestDb.VendedorId, Linea(1, 1));
        await using var db = _testDb.CrearContexto();
        var service = new PedidoService(db, TimeProvider.System);

        Assert.Null(await service.ObtenerAsync(pedido.Numero, TestDb.OtroVendedorId, esAdmin: false));
        Assert.NotNull(await service.ObtenerAsync(pedido.Numero, TestDb.VendedorId, esAdmin: false));
        Assert.NotNull(await service.ObtenerAsync(pedido.Numero, TestDb.AdminId, esAdmin: true));
    }
}
