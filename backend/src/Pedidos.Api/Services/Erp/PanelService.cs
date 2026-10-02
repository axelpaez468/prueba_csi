using Microsoft.EntityFrameworkCore;
using Pedidos.Api.Data;
using Pedidos.Api.Domain;

namespace Pedidos.Api.Services.Erp;

public record ProductoAlertaResponse(int Id, string Codigo, string Nombre, int Stock, int StockMinimo);

public record VentaDiaResponse(DateOnly Fecha, decimal Total);

public record PanelResponse(
    decimal VentasHoy,
    int CantidadVentasHoy,
    decimal VentasMes,
    int CantidadVentasMes,
    // Ventas del mes sin IVA menos su costo.
    decimal UtilidadBrutaMes,
    decimal ComprasMes,
    decimal ValorInventario,
    int OrdenesPendientes,
    List<ProductoAlertaResponse> ProductosBajoMinimo,
    List<VentaDiaResponse> VentasUltimos7Dias);

/// <summary>Indicadores del inicio: ventas, utilidad, inventario y compras pendientes.</summary>
public class PanelService
{
    private readonly AppDbContext _db;
    private readonly TimeProvider _time;

    public PanelService(AppDbContext db, TimeProvider time)
    {
        _db = db;
        _time = time;
    }

    public async Task<PanelResponse> ResumenAsync(CancellationToken ct)
    {
        var hoy = Calendario.Hoy(_time);
        var inicioMes = new DateOnly(hoy.Year, hoy.Month, 1);
        var desde7 = hoy.AddDays(-6);
        var inicioConsulta = Calendario.InicioUtc(inicioMes < desde7 ? inicioMes : desde7);

        // Pocas filas por periodo: se agregan en memoria por día local (la BD guarda UTC).
        var ventas = await _db.Pedidos.AsNoTracking()
            .Where(p => p.Fecha >= inicioConsulta)
            .Select(p => new { p.Fecha, p.Total, p.BaseImponible, p.Costo })
            .ToListAsync(ct);
        var conDia = ventas.Select(v => (Dia: Calendario.FechaLocal(v.Fecha), v.Total, v.BaseImponible, v.Costo)).ToList();
        var delMes = conDia.Where(v => v.Dia >= inicioMes).ToList();
        var deHoy = conDia.Where(v => v.Dia == hoy).ToList();

        var inicioMesUtc = Calendario.InicioUtc(inicioMes);
        var compras = await _db.OrdenesCompra.AsNoTracking()
            .Where(o => o.Estado == EstadosOrden.Recibida && o.FechaRecepcion >= inicioMesUtc)
            .Select(o => o.Total).ToListAsync(ct);

        var inventario = await _db.Productos.AsNoTracking().Select(p => new { p.Stock, p.CostoPromedio }).ToListAsync(ct);
        var bajoMinimo = await _db.Productos.AsNoTracking()
            .Where(p => p.Activo && p.StockMinimo > 0 && p.Stock <= p.StockMinimo)
            .OrderBy(p => p.Stock).ThenBy(p => p.Nombre)
            .Take(10)
            .Select(p => new ProductoAlertaResponse(p.Id, p.Codigo, p.Nombre, p.Stock, p.StockMinimo))
            .ToListAsync(ct);

        return new PanelResponse(
            deHoy.Sum(v => v.Total),
            deHoy.Count,
            delMes.Sum(v => v.Total),
            delMes.Count,
            delMes.Sum(v => v.BaseImponible - v.Costo),
            compras.Sum(),
            Montos.Redondear(inventario.Sum(p => p.Stock * p.CostoPromedio)),
            await _db.OrdenesCompra.CountAsync(o => o.Estado == EstadosOrden.Pendiente, ct),
            bajoMinimo,
            Enumerable.Range(0, 7)
                .Select(i => desde7.AddDays(i))
                .Select(d => new VentaDiaResponse(d, conDia.Where(v => v.Dia == d).Sum(v => v.Total)))
                .ToList());
    }
}
