using Pedidos.Api.Domain;
using Pedidos.Api.Dtos;
using Pedidos.Api.Errors;
using Pedidos.Api.Services.Erp;
using Pedidos.Tests.Infra;

namespace Pedidos.Tests;

public class FichaProductoTests : ErpTestBase
{
    private static GuardarProductoRequest Ficha(string? descripcion = null, List<EspecificacionDto>? specs = null, int garantia = 12) =>
        new("P-030", "Parlante Bluetooth", 350m, 3, null, " SoundMax ", "Audio", descripcion, garantia, specs);

    [Fact]
    public async Task Ficha_SeGuarda_ConPárrafosYEspecificaciones()
    {
        var p = await Inventario().CrearAsync(Ficha(
            "Sonido potente.\r\n\r\n\r\n\r\nResistente al agua   IPX5.",
            new() { new("Potencia", "20 W"), new(" ", " "), new("Batería", "12 horas") }), default);

        Assert.Equal("SoundMax", p.Marca);
        Assert.Equal("Audio", p.Categoria);
        Assert.Equal("Sonido potente.\n\nResistente al agua IPX5.", p.Descripcion); // conserva párrafos, quita excesos
        Assert.Equal(12, p.GarantiaMeses);
        Assert.Equal(new[] { "Potencia", "Batería" }, p.Especificaciones.Select(e => e.Nombre)); // descarta filas vacías

        // Se relee de la BD tal cual (la lista se guarda como JSON).
        var kardex = await Inventario().KardexAsync(p.Id, default);
        Assert.Equal("12 horas", kardex.Producto.Especificaciones[1].Valor);
    }

    [Fact]
    public async Task Especificacion_SinValor_ORepetida_SeRechaza()
    {
        await Assert.ThrowsAsync<BusinessRuleException>(() =>
            Inventario().CrearAsync(Ficha(specs: new() { new("Potencia", "") }), default));
        await Assert.ThrowsAsync<BusinessRuleException>(() =>
            Inventario().CrearAsync(Ficha(specs: new() { new("Potencia", "20 W"), new("potencia", "30 W") }), default));
    }

    [Fact]
    public async Task Descripcion_MuyLarga_OGarantiaFueraDeRango_SeRechaza()
    {
        await Assert.ThrowsAsync<BusinessRuleException>(() =>
            Inventario().CrearAsync(Ficha(new string('x', InventarioService.DescripcionMax + 1)), default));
        await Assert.ThrowsAsync<BusinessRuleException>(() => Inventario().CrearAsync(Ficha(garantia: 121), default));
    }

    [Fact]
    public async Task EditarProducto_ActualizaLaFicha_SinTocarLaExistencia()
    {
        await Inventario().EditarAsync(1, new GuardarProductoRequest(null, "Teclado", 150m, 2, null, "KeyForge", "Periféricos",
            "Teclado mecánico.", 24, new() { new("Switches", "Rojos") }), default);

        var p = await ProductoEnBd(1);
        Assert.Equal("KeyForge", p.Marca);
        Assert.Equal(24, p.GarantiaMeses);
        Assert.Equal("Rojos", Assert.Single(p.Especificaciones).Valor);
        Assert.Equal(10, p.Stock);
    }
}

public class ReporteVentasTests : ErpTestBase
{
    private ReporteVentasService Reportes() => new(Db.CrearContexto());

    private static DateOnly Hoy => Calendario.Hoy(TimeProvider.System);

    [Fact]
    public async Task Reporte_ResumeTotales_IvaUtilidadYTicketPromedio()
    {
        await Vender(1, 2);                       // Teclado: Q300, costo 2 x Q90
        await Vender(2, 1, formaPago: "TARJETA"); // Mouse: Q75.50, costo Q40

        var r = await Reportes().GenerarAsync(Hoy, Hoy, TestDb.AdminId, veTodas: true, default);

        Assert.Equal(2, r.Resumen.Facturas);
        Assert.Equal(3, r.Resumen.Unidades);
        Assert.Equal(375.50m, r.Resumen.Total);
        Assert.Equal(r.Resumen.Total, r.Resumen.BaseImponible + r.Resumen.Iva);
        Assert.Equal(220m, r.Resumen.Costo);
        Assert.Equal(r.Resumen.BaseImponible - 220m, r.Resumen.UtilidadBruta);
        Assert.Equal(187.75m, r.Resumen.TicketPromedio);
        Assert.Equal(0, r.PeriodoAnterior.Facturas);
    }

    [Fact]
    public async Task Reporte_DesglosaPorProducto_FormaDePago_VendedorYDia()
    {
        await Vender(1, 2);
        await Vender(1, 1);
        await Vender(2, 1, formaPago: "TARJETA");

        var r = await Reportes().GenerarAsync(Hoy.AddDays(-2), Hoy, TestDb.AdminId, veTodas: true, default);

        var teclado = r.PorProducto[0]; // ordenado por ventas
        Assert.Equal("P001", teclado.Codigo);
        Assert.Equal(3, teclado.Unidades);
        Assert.Equal(450m, teclado.Total);
        Assert.Equal(270m, teclado.Costo);
        Assert.Equal(teclado.VentasSinIva - 270m, teclado.Utilidad);
        Assert.Equal(100m, r.PorProducto.Sum(p => p.Participacion), 1);

        Assert.Equal(new[] { "EFECTIVO", "TARJETA" }, r.PorFormaPago.Select(f => f.FormaPago));
        Assert.Equal(2, r.PorFormaPago[0].Facturas);
        Assert.Equal("Vendedor Uno", Assert.Single(r.PorVendedor).Vendedor);
        Assert.Equal("CF", Assert.Single(r.PorCliente).Nit);
        Assert.Equal(3, r.PorDia.Count);                  // un registro por día del rango, aunque no haya ventas
        Assert.Equal(525.50m, r.PorDia[^1].Total);
        Assert.Equal("Sin categoría", Assert.Single(r.PorCategoria).Categoria);
    }

    [Fact]
    public async Task Reporte_DelVendedor_SoloIncluyeSusVentas()
    {
        await Vender(1, 1);
        await TestDb.Ventas(Db.CrearContexto()).CrearAsync(TestDb.OtroVendedorId,
            new CrearPedidoRequest(new() { new LineaPedidoRequest(2, 1) }));

        var propio = await Reportes().GenerarAsync(Hoy, Hoy, TestDb.OtroVendedorId, veTodas: false, default);

        Assert.Equal(1, propio.Resumen.Facturas);
        Assert.Equal(75.50m, propio.Resumen.Total);
    }

    [Fact]
    public async Task Reporte_ConRangoInvalido_Falla()
    {
        await Assert.ThrowsAsync<BusinessRuleException>(() =>
            Reportes().GenerarAsync(Hoy, Hoy.AddDays(-1), TestDb.AdminId, true, default));
    }
}
