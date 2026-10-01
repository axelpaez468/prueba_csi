using Microsoft.EntityFrameworkCore;
using Pedidos.Api.Domain;
using Pedidos.Api.Dtos;
using Pedidos.Api.Errors;
using Pedidos.Api.Services.Erp;
using Pedidos.Tests.Infra;

namespace Pedidos.Tests;

public class GeografiaTests
{
    [Fact]
    public void Catalogo_Tiene22Departamentos_Y340Municipios()
    {
        Assert.Equal(22, Geografia.Departamentos.Count);
        Assert.Equal(340, Geografia.Departamentos.Sum(d => d.Municipios.Count));
        Assert.All(Geografia.Departamentos, d => Assert.Equal(d.Municipios.Count, d.Municipios.Distinct().Count()));
    }

    [Theory]
    [InlineData("Quetzaltenango", "Coatepeque")]
    [InlineData("  sacatepequez ", "antigua guatemala")] // sin tildes ni mayúsculas también vale
    public void Validar_DevuelveLosNombresOficiales(string departamento, string municipio)
    {
        var lugar = Geografia.Validar(departamento, municipio);
        Assert.NotNull(lugar);
        Assert.Contains(lugar.Value.Departamento, new[] { "Quetzaltenango", "Sacatepéquez" });
    }

    [Theory]
    [InlineData("Guatemala", "Coatepeque")]   // Coatepeque es de Quetzaltenango
    [InlineData("Narnia", "Guatemala")]
    [InlineData("Guatemala", "")]
    public void Validar_RechazaCombinacionesQueNoExisten(string departamento, string municipio) =>
        Assert.Null(Geografia.Validar(departamento, municipio));
}

public class PipelineTests : ErpTestBase
{
    private PipelineService Pipeline() => new(Db.CrearContexto(), TimeProvider.System);

    private Task<PedidoResponse> VenderConEntrega(string departamento = "Escuintla", string municipio = "Palín") =>
        TestDb.Ventas(Db.CrearContexto()).CrearAsync(TestDb.VendedorId, new CrearPedidoRequest(
            new() { new LineaPedidoRequest(1, 1) }, null, null, "Km 31 carretera al Pacífico", departamento, municipio));

    [Fact]
    public async Task Venta_GuardaLaEntrega_EmpiezaEnNuevo_YQuedaEnElHistorial()
    {
        var v = await VenderConEntrega(" escuintla", "PALIN");

        Assert.Equal("Escuintla", v.Departamento);
        Assert.Equal("Palín", v.Municipio);
        Assert.Equal(EstadosVenta.Nuevo, v.Estado);
        Assert.Equal(EstadosVenta.Nuevo, Assert.Single(v.Historial).Estado);
    }

    [Fact]
    public async Task Venta_ConMunicipioDeOtroDepartamento_SeRechaza()
    {
        var ex = await Assert.ThrowsAsync<BusinessRuleException>(() => VenderConEntrega("Guatemala", "Coatepeque"));
        Assert.Contains("no pertenece", ex.Message);
        Assert.Equal(10, Db.StockDe(1));
    }

    [Fact]
    public async Task Pipeline_CadaRolAvanzaSuEtapa_HastaEntregado()
    {
        var v = await VenderConEntrega();

        Assert.Equal(EstadosVenta.Revisado, await Pipeline().AvanzarAsync(v.Numero, TestDb.VendedorId, Roles.Vendedor, "Datos confirmados", default));
        Assert.Equal(EstadosVenta.Autorizado, await Pipeline().AvanzarAsync(v.Numero, TestDb.AdminId, Roles.Contador, null, default));
        Assert.Equal(EstadosVenta.Despachado, await Pipeline().AvanzarAsync(v.Numero, TestDb.AdminId, Roles.Bodega, null, default));
        Assert.Equal(EstadosVenta.EnCamino, await Pipeline().AvanzarAsync(v.Numero, TestDb.AdminId, Roles.Bodega, null, default));
        Assert.Equal(EstadosVenta.Entregado, await Pipeline().AvanzarAsync(v.Numero, TestDb.AdminId, Roles.Bodega, null, default));
        await Assert.ThrowsAsync<BusinessRuleException>(() =>
            Pipeline().AvanzarAsync(v.Numero, TestDb.AdminId, Roles.Admin, null, default));

        var detalle = await TestDb.Ventas(Db.CrearContexto()).ObtenerAsync(v.Numero, TestDb.AdminId, veTodas: true);
        Assert.Equal(EstadosVenta.Orden, detalle!.Historial.Select(h => h.Estado));
        Assert.Equal("Datos confirmados", detalle.Historial[1].Nota);
    }

    [Theory]
    [InlineData(Roles.Bodega)]    // bodega no revisa
    [InlineData(Roles.Contador)]  // el contador autoriza, pero no revisa
    public async Task Pipeline_UnRolNoPuedeSaltarseEtapasAjenas(string rol)
    {
        var v = await VenderConEntrega();

        var ex = await Assert.ThrowsAsync<BusinessRuleException>(() => Pipeline().AvanzarAsync(v.Numero, TestDb.AdminId, rol, null, default));
        Assert.Contains("Tu rol no puede", ex.Message);
    }

    [Fact]
    public async Task Pipeline_ElVendedorSoloVeYRevisaSusVentas()
    {
        var v = await VenderConEntrega();

        Assert.Empty(await Pipeline().TableroAsync(TestDb.OtroVendedorId, Roles.Vendedor, default));
        await Assert.ThrowsAsync<NoEncontradoException>(() =>
            Pipeline().AvanzarAsync(v.Numero, TestDb.OtroVendedorId, Roles.Vendedor, null, default));

        var tablero = await Pipeline().TableroAsync(TestDb.VendedorId, Roles.Vendedor, default);
        Assert.Equal(EstadosVenta.Revisado, Assert.Single(tablero).PuedeAvanzarA);
        var deBodega = await Pipeline().TableroAsync(TestDb.AdminId, Roles.Bodega, default);
        Assert.Null(Assert.Single(deBodega).PuedeAvanzarA); // está en NUEVO: a bodega aún no le toca
    }

    [Fact]
    public async Task Reporte_AgrupaPorDepartamento_ConElProductoMasVendido()
    {
        await VenderConEntrega("Escuintla", "Palín");
        await TestDb.Ventas(Db.CrearContexto()).CrearAsync(TestDb.VendedorId, new CrearPedidoRequest(
            new() { new LineaPedidoRequest(2, 3) }, null, null, null, "Petén", "Flores"));
        await Vender(1, 1); // sin entrega

        var hoy = Calendario.Hoy(TimeProvider.System);
        var r = await new ReporteVentasService(Db.CrearContexto()).GenerarAsync(hoy, hoy, TestDb.AdminId, true, default);

        var peten = r.PorDepartamento.Single(d => d.Departamento == "Petén");
        Assert.Equal("GT-PE", peten.Iso);
        Assert.Equal("Mouse", peten.ProductoTop);
        Assert.Equal(3, peten.UnidadesProductoTop);
        Assert.Contains(r.PorDepartamento, d => d.Departamento == ReporteVentasService.SinDepartamento);
        Assert.Equal(3, r.PorEstado.Single(e => e.Estado == EstadosVenta.Nuevo).Facturas);
    }
}

public class GeneradorDemoTests : IDisposable
{
    private readonly TestDb _db = new();

    public void Dispose() => _db.Dispose();

    [Fact]
    public async Task Generador_CreaOperacionCompleta_Cuadrada_YSoloUnaVez()
    {
        var generador = new GeneradorDemo(_db.CrearContexto);

        Assert.True(await generador.GenerarAsync(dias: 4, default));
        Assert.False(await new GeneradorDemo(_db.CrearContexto).GenerarAsync(dias: 4, default)); // ya existe el marcador

        await using var db = _db.CrearContexto();
        Assert.Equal(23, await db.Productos.CountAsync());
        Assert.True(await db.Pedidos.CountAsync() > 5);
        Assert.True(await db.Pedidos.AllAsync(p => p.Departamento != null && p.Municipio != null));
        Assert.True(await db.Pedidos.AnyAsync(p => p.Estado == EstadosVenta.Entregado || p.Estado == EstadosVenta.EnCamino
                                                   || p.Estado == EstadosVenta.Despachado || p.Estado == EstadosVenta.Revisado));
        Assert.True(await db.OrdenesCompra.AnyAsync(o => o.Estado == EstadosOrden.Recibida));

        var hoy = Calendario.Hoy(TimeProvider.System);
        var contabilidad = new ContabilidadService(_db.CrearContexto(), TimeProvider.System);
        Assert.True((await contabilidad.BalanceComprobacionAsync(hoy.AddDays(-30), hoy, default)).Cuadra);
        Assert.True((await contabilidad.BalanceGeneralAsync(hoy, default)).Cuadra);
    }
}
