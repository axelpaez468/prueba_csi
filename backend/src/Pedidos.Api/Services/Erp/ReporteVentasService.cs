using Microsoft.EntityFrameworkCore;
using Pedidos.Api.Data;
using Pedidos.Api.Domain;
using Pedidos.Api.Dtos;

namespace Pedidos.Api.Services.Erp;

/// <summary>
/// Reportes de ventas de un rango de fechas: resumen (con el período anterior para comparar), ventas por día,
/// por producto, por categoría, por vendedor, por cliente y por forma de pago.
/// El vendedor solo ve sus propias ventas.
/// </summary>
public class ReporteVentasService
{
    /// <summary>Tope de facturas por consulta: un rango de un año de una pyme cabe de sobra.</summary>
    public const int FacturasMax = 50_000;

    private readonly AppDbContext _db;

    public ReporteVentasService(AppDbContext db) => _db = db;

    private sealed record Linea(int ProductoId, int Cantidad, decimal Subtotal, decimal CostoUnitario);

    private sealed record Venta(int Id, int UsuarioId, int ClienteId, DateTime Fecha, string FormaPago, decimal Total,
        decimal BaseImponible, decimal Iva, decimal Costo, List<Linea> Lineas);

    public async Task<ReporteVentasResponse> GenerarAsync(DateOnly desde, DateOnly hasta, int usuarioId, bool veTodas,
        CancellationToken ct)
    {
        var (inicio, fin) = Calendario.RangoUtc(desde, hasta);
        var dias = hasta.DayNumber - desde.DayNumber + 1;
        var (inicioAnterior, _) = Calendario.RangoUtc(desde.AddDays(-dias), desde.AddDays(-1));

        var ventas = await CargarAsync(inicio, fin, usuarioId, veTodas, ct);
        var anteriores = await CargarAsync(inicioAnterior, inicio, usuarioId, veTodas, ct);

        var productos = await _db.Productos.AsNoTracking()
            .Select(p => new { p.Id, p.Codigo, p.Nombre, p.Categoria })
            .ToDictionaryAsync(p => p.Id, ct);
        var idsVendedores = ventas.Select(v => v.UsuarioId).Distinct().ToList();
        var vendedores = await _db.Usuarios.AsNoTracking().Where(u => idsVendedores.Contains(u.Id))
            .ToDictionaryAsync(u => u.Id, u => u.Username, ct);
        var idsClientes = ventas.Select(v => v.ClienteId).Distinct().ToList();
        var clientes = await _db.Clientes.AsNoTracking().Where(c => idsClientes.Contains(c.Id))
            .ToDictionaryAsync(c => c.Id, c => (c.Nit, c.Nombre), ct);

        var total = ventas.Sum(v => v.Total);
        decimal Parte(decimal monto) => total == 0 ? 0 : Math.Round(monto / total * 100, 1);

        // Líneas con su base sin IVA y su costo, para calcular utilidad por producto y categoría.
        var lineas = ventas.SelectMany(v => v.Lineas).Select(l => new
        {
            l.ProductoId,
            l.Cantidad,
            l.Subtotal,
            Base = Montos.SepararIva(l.Subtotal, Pedido.TasaIva).Base,
            Costo = Montos.Redondear(l.Cantidad * l.CostoUnitario)
        }).ToList();

        var porProducto = lineas.GroupBy(l => l.ProductoId).Select(g =>
        {
            var p = productos.GetValueOrDefault(g.Key);
            var ventasSinIva = g.Sum(x => x.Base);
            var costo = g.Sum(x => x.Costo);
            var subtotal = g.Sum(x => x.Subtotal);
            return new VentaPorProductoResponse(g.Key, p?.Codigo ?? "?", p?.Nombre ?? "Producto eliminado", p?.Categoria,
                g.Sum(x => x.Cantidad), subtotal, ventasSinIva, costo, ventasSinIva - costo, Margen(ventasSinIva, costo),
                Parte(subtotal));
        }).OrderByDescending(x => x.Total).ToList();

        var porCategoria = porProducto.GroupBy(p => p.Categoria ?? "Sin categoría").Select(g =>
            new VentaPorCategoriaResponse(g.Key, g.Sum(x => x.Unidades), g.Sum(x => x.Total), g.Sum(x => x.Utilidad),
                Parte(g.Sum(x => x.Total))))
            .OrderByDescending(x => x.Total).ToList();

        var porVendedor = ventas.GroupBy(v => v.UsuarioId).Select(g =>
            new VentaPorVendedorResponse(g.Key, vendedores.GetValueOrDefault(g.Key, "?"), g.Count(), g.Sum(v => v.Total),
                g.Sum(v => v.BaseImponible - v.Costo), Parte(g.Sum(v => v.Total))))
            .OrderByDescending(x => x.Total).ToList();

        var porCliente = ventas.GroupBy(v => v.ClienteId).Select(g =>
        {
            var (nit, nombre) = clientes.GetValueOrDefault(g.Key, ("?", "?"));
            return new VentaPorClienteResponse(g.Key, Nit.Formatear(nit), nombre, g.Count(), g.Sum(v => v.Total),
                Parte(g.Sum(v => v.Total)));
        }).OrderByDescending(x => x.Total).Take(20).ToList();

        var porFormaPago = ventas.GroupBy(v => v.FormaPago).Select(g =>
            new VentaPorFormaPagoResponse(g.Key, g.Count(), g.Sum(v => v.Total), Parte(g.Sum(v => v.Total))))
            .OrderByDescending(x => x.Total).ToList();

        var porDia = Enumerable.Range(0, dias)
            .Select(i => desde.AddDays(i))
            .Select(d =>
            {
                var delDia = ventas.Where(v => Calendario.FechaLocal(v.Fecha) == d).ToList();
                return new VentaPorDiaResponse(d, delDia.Count, delDia.Sum(v => v.Total));
            })
            .ToList();

        return new ReporteVentasResponse(desde, hasta, Resumir(ventas), Resumir(anteriores), porDia, porProducto,
            porCategoria, porVendedor, porCliente, porFormaPago);
    }

    private async Task<List<Venta>> CargarAsync(DateTime inicio, DateTime fin, int usuarioId, bool veTodas, CancellationToken ct)
    {
        var filas = await _db.Pedidos.AsNoTracking()
            .Where(p => p.Fecha >= inicio && p.Fecha < fin && (veTodas || p.UsuarioId == usuarioId))
            .OrderBy(p => p.Id)
            .Take(FacturasMax)
            .Select(p => new
            {
                p.Id, p.UsuarioId, p.ClienteId, p.Fecha, p.FormaPago, p.Total, p.BaseImponible, p.Iva, p.Costo,
                Lineas = p.Detalles.Select(d => new Linea(d.ProductoId, d.Cantidad, d.Subtotal, d.CostoUnitario)).ToList()
            })
            .AsSplitQuery()
            .ToListAsync(ct);
        return filas.Select(f => new Venta(f.Id, f.UsuarioId, f.ClienteId, f.Fecha, f.FormaPago, f.Total, f.BaseImponible,
            f.Iva, f.Costo, f.Lineas)).ToList();
    }

    private static ResumenVentasResponse Resumir(List<Venta> ventas)
    {
        var total = ventas.Sum(v => v.Total);
        var baseImponible = ventas.Sum(v => v.BaseImponible);
        var costo = ventas.Sum(v => v.Costo);
        return new ResumenVentasResponse(
            ventas.Count,
            ventas.Sum(v => v.Lineas.Sum(l => l.Cantidad)),
            total,
            baseImponible,
            ventas.Sum(v => v.Iva),
            costo,
            baseImponible - costo,
            Margen(baseImponible, costo),
            ventas.Count == 0 ? 0 : Montos.Redondear(total / ventas.Count));
    }

    private static decimal Margen(decimal ventasSinIva, decimal costo) =>
        ventasSinIva == 0 ? 0 : Math.Round((ventasSinIva - costo) / ventasSinIva * 100, 1);
}
