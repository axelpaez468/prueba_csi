using Pedidos.Api.Domain;
using Pedidos.Api.Dtos;
using Pedidos.Api.Errors;
using Pedidos.Api.Services.Erp;
using Pedidos.Tests.Infra;

namespace Pedidos.Tests;

public class PronosticoTests : ErpTestBase
{
    private PronosticoService Pronostico() => new(Db.CrearContexto(), TimeProvider.System);

    private async Task Llevar(int venta, string hasta)
    {
        var estado = EstadosVenta.Nuevo;
        while (estado != hasta)
            estado = await new PipelineService(Db.CrearContexto(), TimeProvider.System)
                .AvanzarAsync(venta, TestDb.AdminId, Roles.Admin, null, default);
    }

    private static DateOnly Hoy => Calendario.Hoy(TimeProvider.System);

    private Task<PronosticoResponse> Generar(bool veTodas = true, int usuario = TestDb.AdminId) =>
        Pronostico().GenerarAsync(Hoy, Hoy, usuario, veTodas, default);

    private static ActualizarProbabilidadesRequest Probabilidades(params decimal[] valores) =>
        new(EstadosVenta.Orden.Select((e, i) => new ProbabilidadEtapaRequest(e, valores[i])).ToList());

    [Fact]
    public async Task Pronostico_EsLoCerradoMasCadaEtapaPorSuProbabilidad()
    {
        var entregada = await Vender(1, 2);
        var autorizada = await Vender(2, 1);
        var nueva = await Vender(3, 1);
        await Llevar(entregada.Numero, EstadosVenta.Entregado);
        await Llevar(autorizada.Numero, EstadosVenta.Autorizado);

        var r = await Generar();

        Assert.Equal(entregada.Total, r.Cerrado);
        Assert.Equal(1, r.FacturasCerradas);
        Assert.Equal(2, r.FacturasAbiertas);
        Assert.Equal(autorizada.Total + nueva.Total, r.Abierto);
        var esperado = Math.Round(autorizada.Total * 0.50m + nueva.Total * 0.10m, 2);
        Assert.Equal(esperado, r.PonderadoAbierto);
        Assert.Equal(entregada.Total + esperado, r.Pronostico);

        var etapa = r.Etapas.Single(e => e.Estado == EstadosVenta.Autorizado);
        Assert.Equal((50m, 1, autorizada.Total, Math.Round(autorizada.Total * 0.5m, 2)),
            (etapa.Probabilidad, etapa.Facturas, etapa.Total, etapa.Ponderado));
        Assert.Equal(EstadosVenta.Orden, r.Etapas.Select(e => e.Estado));
        Assert.Equal(r.Pronostico, r.Etapas.Sum(e => e.Ponderado)); // la etapa "Entregado" pesa 100 %

        var tramo = Assert.Single(r.Tendencia);
        Assert.Equal((r.Cerrado, r.Abierto, r.PonderadoAbierto), (tramo.Cerrado, tramo.Abierto, tramo.Ponderado));
        Assert.Equal(r.Pronostico, Assert.Single(r.PorVendedor).Pronostico);
        Assert.Equal(Math.Round(r.Cerrado / r.Pronostico * 100, 1), r.AvanceCierre);
    }

    [Fact]
    public async Task CambiarProbabilidades_CambiaElPronostico_YGuardaQuienLasCambio()
    {
        var v = await Vender(1, 1);

        await Pronostico().ActualizarProbabilidadesAsync(Probabilidades(40, 50, 60, 80, 95, 100), TestDb.AdminId, default);
        var r = await Generar();

        Assert.Equal(40m, r.Etapas[0].Probabilidad);
        Assert.Equal(Math.Round(v.Total * 0.4m, 2), r.PonderadoAbierto);
        Assert.NotNull(r.ProbabilidadesActualizadasEn);
        Assert.NotNull(r.ProbabilidadesActualizadasPor);
    }

    [Theory]
    [InlineData(new double[] { 10, 25, 50, 75, 90, 90 }, "100 %")]          // entregado siempre 100
    [InlineData(new double[] { 10, 60, 50, 75, 90, 100 }, "menos probabilidad")] // no puede bajar
    [InlineData(new double[] { -5, 25, 50, 75, 90, 100 }, "entre 0 %")]
    public async Task CambiarProbabilidades_Invalidas_SeRechazan(double[] valores, string mensaje)
    {
        var ex = await Assert.ThrowsAsync<BusinessRuleException>(() => Pronostico().ActualizarProbabilidadesAsync(
            Probabilidades(valores.Select(v => (decimal)v).ToArray()), TestDb.AdminId, default));
        Assert.Contains(mensaje, ex.Message);
        Assert.Equal(10m, (await Generar()).Etapas[0].Probabilidad);
    }

    [Fact]
    public async Task CambiarProbabilidades_SinTodasLasEtapas_SeRechaza()
    {
        var request = new ActualizarProbabilidadesRequest(new() { new(EstadosVenta.Nuevo, 20) });
        await Assert.ThrowsAsync<BusinessRuleException>(() =>
            Pronostico().ActualizarProbabilidadesAsync(request, TestDb.AdminId, default));
    }

    [Fact]
    public async Task Vendedor_SoloVeSuPronostico()
    {
        await Vender(1, 1);

        var otro = await Pronostico().GenerarAsync(Hoy, Hoy, TestDb.OtroVendedorId, veTodas: false, default);

        Assert.Equal(0, otro.Pronostico);
        Assert.Empty(otro.PorVendedor);
    }

    [Theory]
    [InlineData("2026-09-01", "2026-09-30", "DIA", 30)]
    [InlineData("2026-07-01", "2026-09-30", "SEMANA", 14)]    // 1 jul. es miércoles: la 1.ª semana va de mié a dom
    [InlineData("2026-01-15", "2026-09-30", "MES", 9)]
    public void Tramos_CubrenElRangoSinHuecos(string desde, string hasta, string agrupacion, int esperados)
    {
        var d = DateOnly.Parse(desde);
        var h = DateOnly.Parse(hasta);
        var tramos = PronosticoService.Tramos(d, h, agrupacion).ToList();

        Assert.Equal(esperados, tramos.Count);
        Assert.Equal(d, tramos[0].Desde);
        Assert.Equal(h, tramos[^1].Hasta);
        for (var i = 1; i < tramos.Count; i++) Assert.Equal(tramos[i - 1].Hasta.AddDays(1), tramos[i].Desde);
        if (agrupacion == "SEMANA") Assert.All(tramos.Skip(1), t => Assert.Equal(DayOfWeek.Monday, t.Desde.DayOfWeek));
    }
}
