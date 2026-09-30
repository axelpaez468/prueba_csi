using Microsoft.EntityFrameworkCore;
using Pedidos.Api.Domain;
using Pedidos.Api.Dtos;
using Pedidos.Api.Errors;
using Pedidos.Api.Services.Erp;
using Pedidos.Tests.Infra;

namespace Pedidos.Tests;

/// <summary>Servicios del ERP sobre la BD de prueba (cada llamada usa un contexto nuevo, como una petición HTTP).</summary>
public abstract class ErpTestBase : IDisposable
{
    protected readonly TestDb Db = new();

    public void Dispose() => Db.Dispose();

    protected ContabilidadService Contabilidad() => new(Db.CrearContexto(), TimeProvider.System);

    protected InventarioService Inventario()
    {
        var db = Db.CrearContexto();
        return new InventarioService(db, new ContabilidadService(db, TimeProvider.System), TimeProvider.System);
    }

    protected CompraService Compras()
    {
        var db = Db.CrearContexto();
        return new CompraService(db, new ContabilidadService(db, TimeProvider.System), TimeProvider.System);
    }

    protected TercerosService Terceros() => new(Db.CrearContexto(), TimeProvider.System);

    protected Task<PedidoResponse> Vender(int productoId, int cantidad, int? clienteId = null, string? formaPago = null) =>
        TestDb.Ventas(Db.CrearContexto()).CrearAsync(TestDb.VendedorId,
            new CrearPedidoRequest(new() { new LineaPedidoRequest(productoId, cantidad) }, clienteId, formaPago));

    protected async Task<ProveedorResponse> ProveedorDePrueba() =>
        await Terceros().CrearProveedorAsync(
            new GuardarProveedorRequest("3344556-7", "Distribuidora Central, S.A.", "Ana Pérez", "2222 0101", null, null, null), default);

    protected async Task<Partida> PartidaDe(string origen, long referenciaId)
    {
        await using var db = Db.CrearContexto();
        return await db.Partidas.AsNoTracking().Include(p => p.Detalles).ThenInclude(d => d.Cuenta)
            .SingleAsync(p => p.Origen == origen && p.ReferenciaId == referenciaId);
    }

    protected static decimal Monto(Partida p, string cuenta, bool debe) =>
        p.Detalles.Where(d => d.Cuenta!.Codigo == cuenta).Sum(d => debe ? d.Debe : d.Haber);

    protected async Task<Producto> ProductoEnBd(int id)
    {
        await using var db = Db.CrearContexto();
        return await db.Productos.AsNoTracking().SingleAsync(p => p.Id == id);
    }

    protected async Task<List<MovimientoInventario>> Kardex(int productoId)
    {
        await using var db = Db.CrearContexto();
        return await db.MovimientosInventario.AsNoTracking().Where(m => m.ProductoId == productoId).OrderBy(m => m.Id).ToListAsync();
    }

    protected async Task<CuentaContable> Cuenta(string codigo)
    {
        await using var db = Db.CrearContexto();
        return await db.CuentasContables.AsNoTracking().SingleAsync(c => c.Codigo == codigo);
    }
}

public class NitTests
{
    [Theory]
    [InlineData("1234567-9", "12345679")]
    [InlineData(" 1000002-k ", "1000002K")]
    [InlineData("8899001K", "8899001K")]
    [InlineData("98765434", "98765434")]
    public void NitValido_SeNormaliza(string entrada, string esperado)
    {
        var nit = Nit.Normalizar(entrada);
        Assert.Equal(esperado, nit);
        Assert.True(Nit.EsValido(nit));
    }

    [Theory]
    [InlineData("12345678")]   // verificador incorrecto
    [InlineData("1000002-9")]
    [InlineData("ABC")]
    [InlineData("")]
    [InlineData("12345679012345")] // demasiado largo
    public void NitInvalido_SeRechaza(string entrada) => Assert.False(Nit.EsValido(Nit.Normalizar(entrada)));

    [Fact]
    public void Formatear_SeparaElVerificador() => Assert.Equal("1234567-9", Nit.Formatear("12345679"));

    [Theory]
    [InlineData(300.00, 267.86, 32.14)]
    [InlineData(75.50, 67.41, 8.09)]
    [InlineData(0.01, 0.01, 0.00)]
    public void SepararIva_LaSumaDaElTotalExacto(double total, double baseEsperada, double ivaEsperado)
    {
        var (b, iva) = Montos.SepararIva((decimal)total, 0.12m);
        Assert.Equal((decimal)baseEsperada, b);
        Assert.Equal((decimal)ivaEsperado, iva);
        Assert.Equal((decimal)total, b + iva);
    }
}

public class VentasTests : ErpTestBase
{
    [Fact]
    public async Task Venta_EmiteFacturaConIvaIncluido_AConsumidorFinal()
    {
        var venta = await Vender(1, 2); // Teclado Q150 x 2

        Assert.Equal("A", venta.Serie);
        Assert.NotEqual(Guid.Empty, venta.Autorizacion);
        Assert.Equal("CF", venta.ClienteNit);
        Assert.Equal(300.00m, venta.Total);
        Assert.Equal(267.86m, venta.BaseImponible);
        Assert.Equal(32.14m, venta.Iva);
        Assert.Equal("EFECTIVO", venta.FormaPago);
        Assert.Equal("Vendedor Uno", venta.Vendedor);
    }

    [Fact]
    public async Task Venta_RegistraLaSalidaEnElKardex_AlCostoPromedio()
    {
        var venta = await Vender(1, 3);

        var movimiento = (await Kardex(1)).Single();
        Assert.Equal(TiposMovimiento.Venta, movimiento.Tipo);
        Assert.Equal(-3, movimiento.Cantidad);
        Assert.Equal(7, movimiento.Saldo);
        Assert.Equal(90m, movimiento.CostoUnitario);
        Assert.Equal($"Factura A-{venta.Numero}", movimiento.Referencia);
    }

    [Fact]
    public async Task Venta_GeneraPartidaCuadrada_ConIvaYCostoDeVentas()
    {
        var venta = await Vender(1, 2);

        var p = await PartidaDe(OrigenesPartida.Venta, venta.Numero);
        Assert.Equal(300.00m, Monto(p, CuentasSistema.Caja, debe: true));
        Assert.Equal(267.86m, Monto(p, CuentasSistema.Ventas, debe: false));
        Assert.Equal(32.14m, Monto(p, CuentasSistema.IvaPorPagar, debe: false));
        Assert.Equal(180.00m, Monto(p, CuentasSistema.CostoVentas, debe: true));   // 2 x Q90
        Assert.Equal(180.00m, Monto(p, CuentasSistema.Inventario, debe: false));
        Assert.Equal(p.Detalles.Sum(d => d.Debe), p.Detalles.Sum(d => d.Haber));
    }

    [Theory]
    [InlineData("TARJETA")]
    [InlineData("transferencia")]
    public async Task Venta_ConTarjetaOTransferencia_EntraABancos(string formaPago)
    {
        var venta = await Vender(2, 1, formaPago: formaPago);

        var p = await PartidaDe(OrigenesPartida.Venta, venta.Numero);
        Assert.Equal(75.50m, Monto(p, CuentasSistema.Bancos, debe: true));
        Assert.Equal(0m, Monto(p, CuentasSistema.Caja, debe: true));
    }

    [Fact]
    public async Task Venta_AClienteConNit_LoMuestraEnLaFactura()
    {
        var cliente = await Terceros().CrearClienteAsync(
            new GuardarClienteRequest("1234567-9", "Comercial La Esquina", "6a. avenida 10-20, zona 1", null, null, null), default);

        var venta = await Vender(1, 1, cliente.Id);

        Assert.Equal("1234567-9", venta.ClienteNit);
        Assert.Equal("Comercial La Esquina", venta.ClienteNombre);
        Assert.Equal("6a. avenida 10-20, zona 1", venta.ClienteDireccion);
    }

    [Fact]
    public async Task Venta_ConFormaDePagoInvalida_Falla_SinTocarElStock()
    {
        await Assert.ThrowsAsync<BusinessRuleException>(() => Vender(1, 1, formaPago: "CREDITO"));
        Assert.Equal(10, Db.StockDe(1));
    }

    [Fact]
    public async Task Venta_DeProductoInactivo_Falla()
    {
        await Inventario().EditarAsync(1, new GuardarProductoRequest(null, "Teclado", 150m, 0, Activo: false), default);

        var ex = await Assert.ThrowsAsync<BusinessRuleException>(() => Vender(1, 1));
        Assert.Contains("ya no está disponible", ex.Message);
    }

    [Fact]
    public async Task Venta_AClienteInactivo_Falla()
    {
        var c = await Terceros().CrearClienteAsync(new GuardarClienteRequest("98765434", "Cliente Viejo", null, null, null, false), default);

        await Assert.ThrowsAsync<BusinessRuleException>(() => Vender(1, 1, c.Id));
    }

    [Fact]
    public async Task Listar_ElVendedorVeSoloSusVentas_YElAdminTodas()
    {
        await Vender(1, 1);
        await TestDb.Ventas(Db.CrearContexto()).CrearAsync(TestDb.OtroVendedorId,
            new CrearPedidoRequest(new() { new LineaPedidoRequest(2, 1) }));
        var hoy = Calendario.Hoy(TimeProvider.System);

        var mias = await TestDb.Ventas(Db.CrearContexto()).ListarAsync(TestDb.VendedorId, veTodas: false, hoy, hoy);
        var todas = await TestDb.Ventas(Db.CrearContexto()).ListarAsync(TestDb.AdminId, veTodas: true, hoy, hoy);

        Assert.Single(mias);
        Assert.Equal(2, todas.Count);
        Assert.All(todas, v => Assert.Equal("CF", v.ClienteNit));
    }
}

public class TercerosTests : ErpTestBase
{
    [Fact]
    public async Task Cliente_ConNitInvalido_OSinNombre_SeRechaza()
    {
        await Assert.ThrowsAsync<BusinessRuleException>(() =>
            Terceros().CrearClienteAsync(new GuardarClienteRequest("1234567-8", "Tienda", null, null, null, null), default));
        await Assert.ThrowsAsync<BusinessRuleException>(() =>
            Terceros().CrearClienteAsync(new GuardarClienteRequest("1234567-9", " ", null, null, null, null), default));
    }

    [Fact]
    public async Task Cliente_ConNitRepetido_SeRechaza_AunqueVengaConOtroFormato()
    {
        await Terceros().CrearClienteAsync(new GuardarClienteRequest("1234567-9", "Tienda Uno", null, null, null, null), default);

        var ex = await Assert.ThrowsAsync<BusinessRuleException>(() =>
            Terceros().CrearClienteAsync(new GuardarClienteRequest("12345679", "Tienda Dos", null, null, null, null), default));
        Assert.Contains("Ya existe", ex.Message);
    }

    [Fact]
    public async Task ConsumidorFinal_NoSeCreaDeNuevo_NiSeModifica()
    {
        await Assert.ThrowsAsync<BusinessRuleException>(() =>
            Terceros().CrearClienteAsync(new GuardarClienteRequest("cf", "Otro CF", null, null, null, null), default));
        await Assert.ThrowsAsync<BusinessRuleException>(() =>
            Terceros().EditarClienteAsync(TestDb.ConsumidorFinalId, new GuardarClienteRequest("CF", "Cambiado", null, null, null, null), default));
    }

    [Fact]
    public async Task Cliente_TelefonoSeGuardaCon502_YBuscarPorNitFunciona()
    {
        var c = await Terceros().CrearClienteAsync(
            new GuardarClienteRequest("8899001-k", "Ferretería El Martillo", null, "5555 0101", "VENTAS@Martillo.gt", null), default);

        Assert.Equal("+50255550101", c.Telefono);
        Assert.Equal("ventas@martillo.gt", c.Email);
        Assert.Equal("8899001-K", c.NitFormateado);
        Assert.Single(await Terceros().ListarClientesAsync("8899001", false, default));
        Assert.Equal("CF", (await Terceros().ListarClientesAsync(null, false, default))[0].Nit); // CF siempre primero
    }

    [Fact]
    public async Task Proveedor_NoPuedeSerConsumidorFinal()
    {
        await Assert.ThrowsAsync<BusinessRuleException>(() =>
            Terceros().CrearProveedorAsync(new GuardarProveedorRequest("CF", "X", null, null, null, null, null), default));
    }
}

public class InventarioTests : ErpTestBase
{
    [Fact]
    public async Task CrearProducto_EmpiezaSinExistencia_YElCodigoEsUnico()
    {
        var p = await Inventario().CrearAsync(new GuardarProductoRequest("p-010", "Parlante Bluetooth", 350m, 5, null), default);

        Assert.Equal("P-010", p.Codigo);
        Assert.Equal(0, p.Stock);
        Assert.Equal(0m, p.CostoPromedio);
        await Assert.ThrowsAsync<BusinessRuleException>(() =>
            Inventario().CrearAsync(new GuardarProductoRequest("P-010", "Otro", 1m, 0, null), default));
    }

    [Theory]
    [InlineData(0)]
    [InlineData(-5)]
    [InlineData(10.555)]
    public async Task CrearProducto_ConPrecioInvalido_Falla(double precio) =>
        await Assert.ThrowsAsync<BusinessRuleException>(() =>
            Inventario().CrearAsync(new GuardarProductoRequest("P-011", "X Producto", (decimal)precio, 0, null), default));

    [Fact]
    public async Task AjusteDeSalida_BajaLaExistencia_YVaAGastoPorFaltantes()
    {
        var mov = await Inventario().AjustarAsync(new AjusteInventarioRequest(1, "SALIDA", 2, null, "Producto dañado en bodega"),
            TestDb.AdminId, default);

        Assert.Equal(8, mov.Saldo);
        Assert.Equal(-2, mov.Cantidad);
        Assert.Equal(90m, mov.CostoUnitario);
        var p = await PartidaDe(OrigenesPartida.Ajuste, mov.Id);
        Assert.Equal(180m, Monto(p, CuentasSistema.FaltantesInventario, debe: true));
        Assert.Equal(180m, Monto(p, CuentasSistema.Inventario, debe: false));
    }

    [Fact]
    public async Task AjusteDeSalida_MayorALaExistencia_Falla_SinCambios()
    {
        await Assert.ThrowsAsync<BusinessRuleException>(() =>
            Inventario().AjustarAsync(new AjusteInventarioRequest(3, "SALIDA", 2, null, "Conteo físico"), TestDb.AdminId, default));

        Assert.Equal(1, Db.StockDe(3));
        Assert.Empty(await Kardex(3));
    }

    [Fact]
    public async Task AjusteDeEntrada_ConCosto_RecalculaElPromedio_YVaAOtrosIngresos()
    {
        // Mouse: 5 u. a Q40. Entran 5 a Q60 -> (5x40 + 5x60) / 10 = Q50.
        var mov = await Inventario().AjustarAsync(new AjusteInventarioRequest(2, "ENTRADA", 5, 60m, "Sobrante en conteo"),
            TestDb.AdminId, default);

        Assert.Equal(10, mov.Saldo);
        Assert.Equal(50m, mov.CostoPromedio);
        var p = await PartidaDe(OrigenesPartida.Ajuste, mov.Id);
        Assert.Equal(300m, Monto(p, CuentasSistema.Inventario, debe: true));
        Assert.Equal(300m, Monto(p, CuentasSistema.OtrosIngresos, debe: false));
    }

    [Fact]
    public async Task AjusteDeEntrada_DeProductoSinCosto_ExigeElCosto()
    {
        var nuevo = await Inventario().CrearAsync(new GuardarProductoRequest("P-020", "Cable HDMI", 60m, 0, null), default);

        await Assert.ThrowsAsync<BusinessRuleException>(() =>
            Inventario().AjustarAsync(new AjusteInventarioRequest(nuevo.Id, "ENTRADA", 3, null, "Inventario inicial"), TestDb.AdminId, default));
    }

    [Fact]
    public async Task Kardex_MuestraLosMovimientosEnOrden_ConElUsuario()
    {
        await Vender(1, 1);
        await Inventario().AjustarAsync(new AjusteInventarioRequest(1, "SALIDA", 1, null, "Muestra para exhibición"), TestDb.AdminId, default);

        var kardex = await Inventario().KardexAsync(1, default);

        Assert.Equal(new[] { TiposMovimiento.Venta, TiposMovimiento.AjusteSalida }, kardex.Movimientos.Select(m => m.Tipo));
        Assert.Equal(new[] { 9, 8 }, kardex.Movimientos.Select(m => m.Saldo));
        Assert.Equal("Admin General", kardex.Movimientos[1].Usuario);
        Assert.Equal(8, kardex.Producto.Stock);
    }

    [Fact]
    public async Task Listar_SoloBajoMinimo_DevuelveLosQueHayQueReabastecer()
    {
        await Inventario().EditarAsync(3, new GuardarProductoRequest(null, "Monitor", 1200m, 2, null), default); // stock 1 <= 2

        var alerta = await Inventario().ListarAsync(null, soloBajoMinimo: true, default);

        Assert.Equal("P003", Assert.Single(alerta).Codigo);
    }
}

public class ComprasTests : ErpTestBase
{
    private async Task<OrdenResponse> OrdenDeTeclados(int cantidad = 10, decimal costo = 110m)
    {
        var proveedor = await ProveedorDePrueba();
        return await Compras().CrearAsync(
            new CrearOrdenRequest(proveedor.Id, new() { new LineaOrdenRequest(1, cantidad, costo) }, "Reposición"), TestDb.AdminId, default);
    }

    [Fact]
    public async Task CrearOrden_CalculaIva_YNoTocaElInventario()
    {
        var orden = await OrdenDeTeclados();

        Assert.Equal(EstadosOrden.Pendiente, orden.Estado);
        Assert.Equal(1100m, orden.Subtotal);
        Assert.Equal(132m, orden.Iva);
        Assert.Equal(1232m, orden.Total);
        Assert.Equal(10, Db.StockDe(1));
    }

    [Fact]
    public async Task RecibirOrden_IngresaMercaderia_RecalculaCostoPromedio_YPagaDesdeBancos()
    {
        var orden = await OrdenDeTeclados(); // Teclado: 10 u. a Q90 + 10 u. a Q110 -> Q100

        var recibida = await Compras().RecibirAsync(orden.Numero, new RecibirOrdenRequest("FACT-A 4521"), TestDb.AdminId, default);

        Assert.Equal(EstadosOrden.Recibida, recibida.Estado);
        Assert.Equal("FACT-A 4521", recibida.FacturaProveedor);
        Assert.Equal("Admin General", recibida.RecibidaPor);
        var producto = await ProductoEnBd(1);
        Assert.Equal(20, producto.Stock);
        Assert.Equal(100m, producto.CostoPromedio);

        var mov = (await Kardex(1)).Single();
        Assert.Equal(TiposMovimiento.Compra, mov.Tipo);
        Assert.Equal(10, mov.Cantidad);
        Assert.Equal(20, mov.Saldo);

        var p = await PartidaDe(OrigenesPartida.Compra, orden.Numero);
        Assert.Equal(1100m, Monto(p, CuentasSistema.Inventario, debe: true));
        Assert.Equal(132m, Monto(p, CuentasSistema.IvaPorCobrar, debe: true));
        Assert.Equal(1232m, Monto(p, CuentasSistema.Bancos, debe: false));
    }

    [Fact]
    public async Task RecibirDosVeces_NoDuplicaElInventario()
    {
        var orden = await OrdenDeTeclados();
        await Compras().RecibirAsync(orden.Numero, new RecibirOrdenRequest("F-1"), TestDb.AdminId, default);

        var ex = await Assert.ThrowsAsync<BusinessRuleException>(() =>
            Compras().RecibirAsync(orden.Numero, new RecibirOrdenRequest("F-1"), TestDb.AdminId, default));
        Assert.Contains("recibida", ex.Message);
        Assert.Equal(20, Db.StockDe(1));
    }

    [Fact]
    public async Task RecibirSinFacturaDelProveedor_Falla()
    {
        var orden = await OrdenDeTeclados();

        await Assert.ThrowsAsync<BusinessRuleException>(() =>
            Compras().RecibirAsync(orden.Numero, new RecibirOrdenRequest("  "), TestDb.AdminId, default));
        Assert.Equal(EstadosOrden.Pendiente, (await Compras().ObtenerAsync(orden.Numero, default))!.Estado);
    }

    [Fact]
    public async Task OrdenAnulada_NoSePuedeRecibir_YUnaRecibidaNoSeAnula()
    {
        var anulada = await OrdenDeTeclados();
        await Compras().AnularAsync(anulada.Numero, default);
        await Assert.ThrowsAsync<BusinessRuleException>(() =>
            Compras().RecibirAsync(anulada.Numero, new RecibirOrdenRequest("F-2"), TestDb.AdminId, default));

        var recibida = await Compras().CrearAsync(
            new CrearOrdenRequest(anulada.ProveedorId, new() { new LineaOrdenRequest(2, 1, 40m) }, null), TestDb.AdminId, default);
        await Compras().RecibirAsync(recibida.Numero, new RecibirOrdenRequest("F-3"), TestDb.AdminId, default);
        await Assert.ThrowsAsync<BusinessRuleException>(() => Compras().AnularAsync(recibida.Numero, default));
    }

    [Theory]
    [InlineData(0, 10)]
    [InlineData(5, 0)]
    [InlineData(5, 10.123)]
    public async Task CrearOrden_ConCantidadOCostoInvalido_Falla(int cantidad, double costo)
    {
        var proveedor = await ProveedorDePrueba();
        await Assert.ThrowsAsync<BusinessRuleException>(() => Compras().CrearAsync(
            new CrearOrdenRequest(proveedor.Id, new() { new LineaOrdenRequest(1, cantidad, (decimal)costo) }, null), TestDb.AdminId, default));
    }
}

public class ContabilidadTests : ErpTestBase
{
    private async Task<PartidaResponse> Manual(params (string Cuenta, decimal Debe, decimal Haber)[] lineas)
    {
        var detalle = new List<LineaPartidaRequest>();
        foreach (var l in lineas)
            detalle.Add(new LineaPartidaRequest((await Cuenta(l.Cuenta)).Id, l.Debe, l.Haber));
        return await Contabilidad().CrearManualAsync(new CrearPartidaRequest(null, "Partida de prueba", detalle), TestDb.AdminId, default);
    }

    [Fact]
    public async Task PartidaManual_QueCuadra_SeRegistra()
    {
        var p = await Manual(("1102", 50_000m, 0), ("3101", 0, 50_000m));

        Assert.Equal(OrigenesPartida.Manual, p.Origen);
        Assert.Equal(50_000m, p.Total);
        Assert.Equal("1102", p.Lineas[0].Codigo); // primero los cargos
    }

    [Fact]
    public async Task PartidaManual_QueNoCuadra_SeRechaza()
    {
        var ex = await Assert.ThrowsAsync<BusinessRuleException>(() => Manual(("6102", 3_000m, 0), ("1102", 0, 2_500m)));
        Assert.Contains("no cuadra", ex.Message);
    }

    [Fact]
    public async Task PartidaManual_ConLineaEnDebeYHaber_OConUnaSolaLinea_SeRechaza()
    {
        await Assert.ThrowsAsync<BusinessRuleException>(() => Manual(("6102", 100m, 100m), ("1102", 0, 0)));
        await Assert.ThrowsAsync<BusinessRuleException>(() => Manual(("6102", 100m, 0)));
    }

    [Fact]
    public async Task PartidaManual_ConFechaFutura_SeRechaza()
    {
        var bancos = await Cuenta("1102");
        var capital = await Cuenta("3101");
        await Assert.ThrowsAsync<BusinessRuleException>(() => Contabilidad().CrearManualAsync(
            new CrearPartidaRequest(Calendario.Hoy(TimeProvider.System).AddDays(1), "Aporte",
                new() { new(bancos.Id, 10m, 0), new(capital.Id, 0, 10m) }), TestDb.AdminId, default));
    }

    [Fact]
    public async Task CuentaDelSistema_NoSeDesactiva_YUnaNuevaTomaElTipoDelCodigo()
    {
        var caja = await Cuenta(CuentasSistema.Caja);
        await Assert.ThrowsAsync<BusinessRuleException>(() =>
            Contabilidad().EditarCuentaAsync(caja.Id, new GuardarCuentaRequest(null, "Caja", false), default));

        var nueva = await Contabilidad().CrearCuentaAsync(new GuardarCuentaRequest("6106", "Publicidad", null), default);
        Assert.Equal(TiposCuenta.Gasto, nueva.Tipo);
        await Assert.ThrowsAsync<BusinessRuleException>(() =>
            Contabilidad().CrearCuentaAsync(new GuardarCuentaRequest("7101", "Tipo inexistente", null), default));
    }

    [Fact]
    public async Task CuentaInactiva_NoRecibeMovimientosManuales()
    {
        var nueva = await Contabilidad().CrearCuentaAsync(new GuardarCuentaRequest("6106", "Publicidad", null), default);
        await Contabilidad().EditarCuentaAsync(nueva.Id, new GuardarCuentaRequest(null, "Publicidad", false), default);

        await Assert.ThrowsAsync<BusinessRuleException>(() => Manual(("6106", 100m, 0), ("1101", 0, 100m)));
    }

    /// <summary>Un mes de operación completo: aporte de capital, compra, venta, ajuste y gasto.</summary>
    private async Task OperarUnMes()
    {
        await Manual(("1102", 20_000m, 0), ("3101", 0, 20_000m));                          // aporte de capital
        var proveedor = await ProveedorDePrueba();
        var orden = await Compras().CrearAsync(
            new CrearOrdenRequest(proveedor.Id, new() { new LineaOrdenRequest(1, 10, 110m) }, null), TestDb.AdminId, default);
        await Compras().RecibirAsync(orden.Numero, new RecibirOrdenRequest("F-100"), TestDb.AdminId, default);  // 1,232 desde bancos
        await Vender(1, 2);                                                                 // Q300 al costo Q100 c/u
        await Inventario().AjustarAsync(new AjusteInventarioRequest(2, "SALIDA", 1, null, "Mouse dañado"), TestDb.AdminId, default);
        await Manual(("6102", 1_500m, 0), ("1102", 0, 1_500m));                             // alquiler
    }

    [Fact]
    public async Task EstadoDeResultados_CalculaUtilidadBrutaYNeta()
    {
        await OperarUnMes();
        var hoy = Calendario.Hoy(TimeProvider.System);

        var er = await Contabilidad().EstadoResultadosAsync(hoy.AddDays(-1), hoy, default);

        Assert.Equal(267.86m, er.TotalIngresos);   // ventas sin IVA
        Assert.Equal(200.00m, er.TotalCostos);     // 2 teclados a Q100 (costo promedio tras la compra)
        Assert.Equal(67.86m, er.UtilidadBruta);
        Assert.Equal(1_540.00m, er.TotalGastos);   // alquiler 1,500 + mouse dañado 40
        Assert.Equal(-1_472.14m, er.UtilidadNeta);
    }

    [Fact]
    public async Task BalanceDeComprobacion_Y_BalanceGeneral_Cuadran()
    {
        await OperarUnMes();
        var hoy = Calendario.Hoy(TimeProvider.System);

        var bc = await Contabilidad().BalanceComprobacionAsync(hoy.AddDays(-30), hoy, default);
        Assert.True(bc.Cuadra);
        Assert.Equal(bc.TotalDebe, bc.TotalHaber);

        var bg = await Contabilidad().BalanceGeneralAsync(hoy, default);
        Assert.True(bg.Cuadra);
        Assert.Equal(bg.TotalActivos, bg.TotalPasivoYCapital);
        Assert.Equal(-1_472.14m, bg.ResultadoDelEjercicio);
        Assert.Equal(32.14m, bg.Pasivos.Single(r => r.Codigo == CuentasSistema.IvaPorPagar).Monto);
    }

    [Fact]
    public async Task LibroMayor_DeBancos_LlevaElSaldoAcumulado()
    {
        await OperarUnMes();
        var hoy = Calendario.Hoy(TimeProvider.System);
        var bancos = await Cuenta(CuentasSistema.Bancos);

        var mayor = await Contabilidad().LibroMayorAsync(bancos.Id, hoy.AddDays(-1), hoy, default);

        Assert.Equal(0m, mayor.SaldoInicial);
        Assert.Equal(new[] { 20_000m, 18_768m, 17_268m }, mayor.Movimientos.Select(m => m.Saldo));
        Assert.Equal(17_268m, mayor.SaldoFinal);
        Assert.Equal(17_268m, mayor.Cuenta.Saldo);
    }

    [Fact]
    public async Task LibroDiario_FiltraPorOrigen()
    {
        await OperarUnMes();
        var hoy = Calendario.Hoy(TimeProvider.System);

        var todas = await Contabilidad().LibroDiarioAsync(hoy, hoy, null, default);
        var ventas = await Contabilidad().LibroDiarioAsync(hoy, hoy, "venta", default);

        Assert.Equal(5, todas.Count);
        Assert.Equal(OrigenesPartida.Venta, Assert.Single(ventas).Origen);
    }

    [Fact]
    public async Task Panel_ResumeVentasDelDia_YProductosBajoMinimo()
    {
        await Vender(1, 2);
        await Inventario().EditarAsync(3, new GuardarProductoRequest(null, "Monitor", 1200m, 1, null), default);

        var panel = await new PanelService(Db.CrearContexto(), TimeProvider.System).ResumenAsync(default);

        Assert.Equal(300m, panel.VentasHoy);
        Assert.Equal(1, panel.CantidadVentasHoy);
        Assert.Equal(87.86m, panel.UtilidadBrutaMes); // base 267.86 - costo 180
        Assert.Equal("P003", Assert.Single(panel.ProductosBajoMinimo).Codigo);
        Assert.Equal(7, panel.VentasUltimos7Dias.Count);
        Assert.Equal(300m, panel.VentasUltimos7Dias[^1].Total);
    }
}
