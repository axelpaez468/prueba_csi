using Microsoft.EntityFrameworkCore;
using Pedidos.Api.Data;
using Pedidos.Api.Domain;
using Pedidos.Api.Dtos;
using Pedidos.Api.Errors;

namespace Pedidos.Api.Services.Erp;

/// <summary>
/// Órdenes de compra de contado. Flujo: COMPRAS crea la orden (PENDIENTE) → BODEGA recibe la mercadería con la
/// factura del proveedor (RECIBIDA: entra al inventario y se paga desde Bancos) o COMPRAS la anula (ANULADA).
/// </summary>
public class CompraService
{
    public const int LineasPorOrdenMax = 50;
    public const int CantidadPorLineaMax = 100_000;

    private readonly AppDbContext _db;
    private readonly ContabilidadService _contabilidad;
    private readonly TimeProvider _time;

    public CompraService(AppDbContext db, ContabilidadService contabilidad, TimeProvider time)
    {
        _db = db;
        _contabilidad = contabilidad;
        _time = time;
    }

    public async Task<OrdenResponse> CrearAsync(CrearOrdenRequest r, int usuarioId, CancellationToken ct)
    {
        var proveedor = await _db.Proveedores.AsNoTracking().FirstOrDefaultAsync(p => p.Id == r.ProveedorId, ct)
                        ?? throw new BusinessRuleException("El proveedor no existe.");
        if (!proveedor.Activo)
            throw new BusinessRuleException($"El proveedor '{proveedor.Nombre}' está inactivo.");

        var lineas = r.Lineas ?? new();
        if (lineas.Count == 0)
            throw new BusinessRuleException("La orden debe tener al menos un producto.");
        if (lineas.Count > LineasPorOrdenMax)
            throw new BusinessRuleException($"Una orden admite como máximo {LineasPorOrdenMax} productos distintos.");
        if (lineas.Any(l => l is null))
            throw new BusinessRuleException("Hay una línea de la orden vacía.");
        var duplicado = lineas.GroupBy(l => l.ProductoId).FirstOrDefault(g => g.Count() > 1);
        if (duplicado is not null)
            throw new BusinessRuleException($"El producto {duplicado.Key} aparece más de una vez. Agrupa las cantidades en una línea.");
        foreach (var l in lineas)
        {
            if (l.Cantidad <= 0 || l.Cantidad > CantidadPorLineaMax)
                throw new BusinessRuleException($"La cantidad del producto {l.ProductoId} debe estar entre 1 y {CantidadPorLineaMax:N0}.");
            if (l.CostoUnitario <= 0 || l.CostoUnitario > InventarioService.PrecioMax || !Montos.TieneCentavosValidos(l.CostoUnitario))
                throw new BusinessRuleException($"El costo del producto {l.ProductoId} debe ser mayor que cero y con máximo dos decimales.");
        }

        var ids = lineas.Select(l => l.ProductoId).ToList();
        var productos = await _db.Productos.AsNoTracking().Where(p => ids.Contains(p.Id)).ToDictionaryAsync(p => p.Id, ct);
        var inexistente = ids.FirstOrDefault(id => !productos.ContainsKey(id));
        if (inexistente != 0)
            throw new BusinessRuleException($"No existe el producto con id {inexistente}.");
        var inactivo = productos.Values.FirstOrDefault(p => !p.Activo);
        if (inactivo is not null)
            throw new BusinessRuleException($"El producto '{inactivo.Nombre}' está inactivo y no se puede comprar.");

        var orden = new OrdenCompra
        {
            ProveedorId = proveedor.Id,
            Fecha = _time.GetUtcNow().UtcDateTime,
            Estado = EstadosOrden.Pendiente,
            Observaciones = Contacto.Opcional(r.Observaciones, 300, "Las observaciones"),
            UsuarioId = usuarioId,
            Detalles = lineas.Select(l => new OrdenCompraDetalle
            {
                ProductoId = l.ProductoId,
                Cantidad = l.Cantidad,
                CostoUnitario = l.CostoUnitario,
                Subtotal = Montos.Redondear(l.Cantidad * l.CostoUnitario)
            }).ToList()
        };
        orden.Subtotal = orden.Detalles.Sum(d => d.Subtotal);
        orden.Iva = Montos.Redondear(orden.Subtotal * Pedido.TasaIva);
        orden.Total = orden.Subtotal + orden.Iva;
        if (orden.Total > Montos.Maximo)
            throw new BusinessRuleException("El total de la orden excede el máximo permitido.");

        _db.OrdenesCompra.Add(orden);
        await _db.SaveChangesAsync(ct);
        return (await ObtenerAsync(orden.Id, ct))!;
    }

    public async Task<List<OrdenResumenResponse>> ListarAsync(string? estado, CancellationToken ct)
    {
        var q = _db.OrdenesCompra.AsNoTracking();
        if (!string.IsNullOrWhiteSpace(estado)) q = q.Where(o => o.Estado == estado.Trim().ToUpperInvariant());
        return await q.OrderByDescending(o => o.Id).Take(500)
            .Select(o => new OrdenResumenResponse(o.Id, o.Fecha, o.Estado, o.Proveedor!.Nombre, o.Detalles.Count, o.Total,
                o.FacturaProveedor))
            .ToListAsync(ct);
    }

    public async Task<OrdenResponse?> ObtenerAsync(int id, CancellationToken ct)
    {
        var o = await _db.OrdenesCompra.AsNoTracking()
            .Include(x => x.Proveedor)
            .Include(x => x.Detalles).ThenInclude(d => d.Producto)
            .FirstOrDefaultAsync(x => x.Id == id, ct);
        if (o is null) return null;

        var usuarios = await _db.Usuarios.AsNoTracking()
            .Where(u => u.Id == o.UsuarioId || u.Id == o.RecibidaPorId)
            .ToDictionaryAsync(u => u.Id, u => u.Username, ct);
        return new OrdenResponse(o.Id, o.Fecha, o.Estado, o.ProveedorId, Nit.Formatear(o.Proveedor!.Nit), o.Proveedor.Nombre,
            o.Subtotal, o.Iva, o.Total, o.Observaciones, usuarios.GetValueOrDefault(o.UsuarioId, "?"), o.FechaRecepcion,
            o.RecibidaPorId is { } r ? usuarios.GetValueOrDefault(r) : null, o.FacturaProveedor,
            o.Detalles.OrderBy(d => d.ProductoId)
                .Select(d => new LineaOrdenResponse(d.ProductoId, d.Producto!.Codigo, d.Producto.Nombre, d.Cantidad,
                    d.CostoUnitario, d.Subtotal))
                .ToList());
    }

    /// <summary>
    /// Recepción total de la mercadería. El cambio de estado es condicional (solo si sigue PENDIENTE): si dos
    /// personas la reciben a la vez, solo una lo logra y el inventario no se duplica.
    /// </summary>
    public async Task<OrdenResponse> RecibirAsync(int id, RecibirOrdenRequest r, int usuarioId, CancellationToken ct)
    {
        var factura = Contacto.Requerido(r.FacturaProveedor, 1, 40, "El número de factura del proveedor");
        var ahora = _time.GetUtcNow().UtcDateTime;

        await using var tx = await _db.Database.BeginTransactionAsync(ct);
        var cambiada = await _db.OrdenesCompra
            .Where(o => o.Id == id && o.Estado == EstadosOrden.Pendiente)
            .ExecuteUpdateAsync(s => s
                .SetProperty(o => o.Estado, EstadosOrden.Recibida)
                .SetProperty(o => o.FechaRecepcion, ahora)
                .SetProperty(o => o.RecibidaPorId, usuarioId)
                .SetProperty(o => o.FacturaProveedor, factura), ct);
        if (cambiada == 0)
            throw await ErrorDeEstadoAsync(id, "recibir", ct);

        var orden = await _db.OrdenesCompra.AsNoTracking()
            .Include(o => o.Detalles).Include(o => o.Proveedor)
            .SingleAsync(o => o.Id == id, ct);

        var referencia = $"OC-{orden.Id}, factura {factura}";
        foreach (var d in orden.Detalles.OrderBy(d => d.ProductoId))
        {
            await Existencias.IngresarAsync(_db, d.ProductoId, d.Cantidad, d.CostoUnitario, ct);
            await Existencias.RegistrarMovimientoAsync(_db, d.ProductoId, TiposMovimiento.Compra, d.Cantidad,
                d.CostoUnitario, referencia, usuarioId, ahora, ct);
        }

        await _contabilidad.RegistrarAutomaticaAsync(OrigenesPartida.Compra, orden.Id,
            $"Compra OC-{orden.Id} a {orden.Proveedor!.Nombre}, factura {factura}", usuarioId,
            new[]
            {
                LineaAsiento.Cargo(CuentasSistema.Inventario, orden.Subtotal),
                LineaAsiento.Cargo(CuentasSistema.IvaPorCobrar, orden.Iva),
                LineaAsiento.Abono(CuentasSistema.Bancos, orden.Total)
            }, ct);

        await _db.SaveChangesAsync(ct);
        await tx.CommitAsync(ct);
        return (await ObtenerAsync(id, ct))!;
    }

    public async Task<OrdenResponse> AnularAsync(int id, CancellationToken ct)
    {
        var cambiada = await _db.OrdenesCompra
            .Where(o => o.Id == id && o.Estado == EstadosOrden.Pendiente)
            .ExecuteUpdateAsync(s => s.SetProperty(o => o.Estado, EstadosOrden.Anulada), ct);
        if (cambiada == 0)
            throw await ErrorDeEstadoAsync(id, "anular", ct);
        return (await ObtenerAsync(id, ct))!;
    }

    private async Task<Exception> ErrorDeEstadoAsync(int id, string accion, CancellationToken ct)
    {
        var estado = await _db.OrdenesCompra.AsNoTracking().Where(o => o.Id == id).Select(o => o.Estado).FirstOrDefaultAsync(ct);
        return estado is null
            ? new NoEncontradoException("Orden de compra no encontrada.")
            : new BusinessRuleException($"No se puede {accion} la orden: está {estado.ToLowerInvariant()}.");
    }
}
