using Microsoft.EntityFrameworkCore;
using Pedidos.Api.Data;
using Pedidos.Api.Domain;
using Pedidos.Api.Dtos;
using Pedidos.Api.Errors;

namespace Pedidos.Api.Services.Erp;

/// <summary>
/// Pronóstico de ventas según el pipeline. Cada etapa tiene una probabilidad de cierre; el valor esperado de una
/// venta abierta es su total por la probabilidad de su etapa. Pronóstico = cerrado (entregado) + esperado de las abiertas.
/// El vendedor ve solo sus ventas.
/// </summary>
public class PronosticoService
{
    private readonly AppDbContext _db;
    private readonly TimeProvider _time;

    public PronosticoService(AppDbContext db, TimeProvider time)
    {
        _db = db;
        _time = time;
    }

    private sealed record Venta(int UsuarioId, DateOnly Dia, decimal Total, string Estado);

    public async Task<PronosticoResponse> GenerarAsync(DateOnly desde, DateOnly hasta, int usuarioId, bool veTodas, CancellationToken ct)
    {
        if (hasta < desde) throw new BusinessRuleException("La fecha final no puede ser anterior a la inicial.");
        var (inicio, fin) = Calendario.RangoUtc(desde, hasta);

        var etapas = await _db.EtapasPipeline.AsNoTracking().ToListAsync(ct);
        var probabilidad = EstadosVenta.Orden.ToDictionary(e => e,
            e => etapas.FirstOrDefault(x => x.Estado == e)?.Probabilidad ?? EstadosVenta.ProbabilidadInicial[e]);
        var ultimaEdicion = etapas.Where(x => x.ActualizadoEn != null).MaxBy(x => x.ActualizadoEn);

        var filas = await _db.Pedidos.AsNoTracking()
            .Where(p => p.Fecha >= inicio && p.Fecha < fin && (veTodas || p.UsuarioId == usuarioId))
            .Take(ReporteVentasService.FacturasMax)
            .Select(p => new { p.UsuarioId, p.Fecha, p.Total, p.Estado })
            .ToListAsync(ct);
        var ventas = filas.Select(f => new Venta(f.UsuarioId, Calendario.FechaLocal(f.Fecha), f.Total, f.Estado)).ToList();

        // Sin redondear por venta: se redondea solo el resultado, para que las sumas cuadren.
        decimal Esperado(Venta v) => v.Total * probabilidad[v.Estado] / 100;
        static bool Cerrada(Venta v) => v.Estado == EstadosVenta.Entregado;

        var porEtapa = EstadosVenta.Orden.Select(e =>
        {
            var deLaEtapa = ventas.Where(v => v.Estado == e).ToList();
            return new EtapaPronosticoResponse(e, EstadosVenta.Nombre(e), probabilidad[e], deLaEtapa.Count,
                deLaEtapa.Sum(v => v.Total), Montos.Redondear(deLaEtapa.Sum(Esperado)));
        }).ToList();

        var cerradas = ventas.Where(Cerrada).ToList();
        var abiertas = ventas.Where(v => !Cerrada(v)).ToList();
        var cerrado = cerradas.Sum(v => v.Total);
        var abierto = abiertas.Sum(v => v.Total);
        // Suma de lo esperado de cada etapa (ya redondeado), para que cuadre al centavo con la tabla por etapa.
        var ponderado = porEtapa.Where(e => e.Estado != EstadosVenta.Entregado).Sum(e => e.Ponderado);
        var pronostico = cerrado + ponderado;

        var agrupacion = (hasta.DayNumber - desde.DayNumber + 1) switch
        {
            <= 31 => "DIA",
            <= 120 => "SEMANA",
            _ => "MES"
        };
        var tendencia = Tramos(desde, hasta, agrupacion).Select(t =>
        {
            var delTramo = ventas.Where(v => v.Dia >= t.Desde && v.Dia <= t.Hasta).ToList();
            return new PronosticoPeriodoResponse(t.Desde, t.Hasta,
                delTramo.Where(Cerrada).Sum(v => v.Total),
                delTramo.Where(v => !Cerrada(v)).Sum(v => v.Total),
                Montos.Redondear(delTramo.Where(v => !Cerrada(v)).Sum(Esperado)));
        }).ToList();

        var ids = ventas.Select(v => v.UsuarioId).Distinct().ToList();
        var vendedores = await _db.Usuarios.AsNoTracking().Where(u => ids.Contains(u.Id))
            .ToDictionaryAsync(u => u.Id, u => u.Username, ct);
        var porVendedor = ventas.GroupBy(v => v.UsuarioId).Select(g =>
        {
            var c = g.Where(Cerrada).Sum(v => v.Total);
            var p = Montos.Redondear(g.Where(v => !Cerrada(v)).Sum(Esperado));
            return new PronosticoVendedorResponse(g.Key, vendedores.GetValueOrDefault(g.Key, "?"), g.Count(), c,
                g.Where(v => !Cerrada(v)).Sum(v => v.Total), p, c + p);
        }).OrderByDescending(x => x.Pronostico).ToList();

        return new PronosticoResponse(desde, hasta, agrupacion, cerradas.Count, cerrado, abiertas.Count, abierto, ponderado,
            pronostico,
            abierto == 0 ? 0 : Math.Round(ponderado / abierto * 100, 1),
            pronostico == 0 ? 0 : Math.Round(cerrado / pronostico * 100, 1),
            porEtapa, tendencia, porVendedor, ultimaEdicion?.ActualizadoEn, ultimaEdicion?.ActualizadoPor);
    }

    /// <summary>
    /// Cambia las probabilidades de cierre. Deben venir las seis etapas, de 0 a 100 %, sin bajar de una etapa a la
    /// siguiente (más avanzada = más probable) y "Entregado" en 100 % porque ya está cerrada.
    /// </summary>
    public async Task ActualizarProbabilidadesAsync(ActualizarProbabilidadesRequest request, int usuarioId, CancellationToken ct)
    {
        var nuevas = request.Etapas ?? new();
        if (nuevas.Any(e => e is null || e.Estado is null) ||
            nuevas.Count != EstadosVenta.Orden.Length || nuevas.Select(e => e.Estado).Distinct().Count() != nuevas.Count ||
            nuevas.Any(e => !EstadosVenta.Orden.Contains(e.Estado)))
            throw new BusinessRuleException("Envía la probabilidad de cada una de las seis etapas, una vez cada una.");

        var valores = EstadosVenta.Orden.Select(e => (Estado: e, Valor: Math.Round(nuevas.Single(x => x.Estado == e).Probabilidad, 2))).ToList();
        if (valores.Any(v => v.Valor is < 0 or > 100))
            throw new BusinessRuleException("Cada probabilidad debe estar entre 0 % y 100 %.");
        if (valores[^1].Valor != 100)
            throw new BusinessRuleException("Una venta entregada y cobrada ya está cerrada: su probabilidad es 100 %.");
        for (var i = 1; i < valores.Count; i++)
            if (valores[i].Valor < valores[i - 1].Valor)
                throw new BusinessRuleException(
                    $"\"{EstadosVenta.Nombre(valores[i].Estado)}\" no puede tener menos probabilidad que \"{EstadosVenta.Nombre(valores[i - 1].Estado)}\": " +
                    "una venta más avanzada tiene más probabilidad de cerrarse.");

        var quien = await _db.Usuarios.AsNoTracking().Where(u => u.Id == usuarioId).Select(u => u.Username).FirstOrDefaultAsync(ct);
        var ahora = _time.GetUtcNow().UtcDateTime;
        var actuales = await _db.EtapasPipeline.ToDictionaryAsync(e => e.Estado, ct);
        foreach (var (estado, valor) in valores)
        {
            if (!actuales.TryGetValue(estado, out var etapa))
                _db.EtapasPipeline.Add(etapa = new EtapaPipeline { Estado = estado });
            etapa.Probabilidad = valor;
            etapa.ActualizadoEn = ahora;
            etapa.ActualizadoPor = quien;
        }
        await _db.SaveChangesAsync(ct);
    }

    /// <summary>Tramos consecutivos que cubren el rango: días, semanas (de lunes a domingo) o meses, recortados al rango.</summary>
    public static IEnumerable<(DateOnly Desde, DateOnly Hasta)> Tramos(DateOnly desde, DateOnly hasta, string agrupacion)
    {
        var inicio = desde;
        while (inicio <= hasta)
        {
            var fin = agrupacion switch
            {
                "DIA" => inicio,
                "SEMANA" => inicio.AddDays((7 - ((int)inicio.DayOfWeek + 6) % 7) - 1),
                _ => new DateOnly(inicio.Year, inicio.Month, 1).AddMonths(1).AddDays(-1)
            };
            if (fin > hasta) fin = hasta;
            yield return (inicio, fin);
            inicio = fin.AddDays(1);
        }
    }
}
