using Microsoft.EntityFrameworkCore;
using Pedidos.Api.Data;
using Pedidos.Api.Domain;
using Pedidos.Api.Dtos;
using Pedidos.Api.Errors;
using Pedidos.Api.Security;
using Pedidos.Api.Services.Erp;

namespace Pedidos.Api.Services;

/// <summary>
/// Ventas de contado. En una sola transacción: descuenta la existencia, emite la factura, registra la salida
/// en el kardex (al costo promedio) y la partida contable (venta con IVA y costo de ventas).
/// </summary>
public class PedidoService
{
    private readonly AppDbContext _db;
    private readonly TimeProvider _time;
    private readonly ContabilidadService _contabilidad;

    public PedidoService(AppDbContext db, TimeProvider time, ContabilidadService contabilidad)
    {
        _db = db;
        _time = time;
        _contabilidad = contabilidad;
    }

    public async Task<PedidoResponse> CrearAsync(int usuarioId, CrearPedidoRequest request, CancellationToken ct = default)
    {
        var lineas = ValidarLineas(request.Lineas);
        var formaPago = (request.FormaPago ?? FormasPago.Efectivo).Trim().ToUpperInvariant();
        if (!FormasPago.Todas.Contains(formaPago))
            throw new BusinessRuleException("La forma de pago debe ser EFECTIVO, TARJETA o TRANSFERENCIA.");
        var cliente = await ClienteDeLaVentaAsync(request.ClienteId, ct);
        var ids = lineas.Select(l => l.ProductoId).ToList();

        // Cabecera, detalle, existencias, kardex y partida en una sola transacción:
        // si algo falla antes del Commit, el Dispose hace rollback de todo.
        await using var tx = await _db.Database.BeginTransactionAsync(ct);

        var productos = await _db.Productos.AsNoTracking()
            .Where(p => ids.Contains(p.Id))
            .ToDictionaryAsync(p => p.Id, ct);

        var inexistentes = ids.Where(id => !productos.ContainsKey(id)).ToList();
        if (inexistentes.Count > 0)
            throw new BusinessRuleException($"No existe el producto con id: {string.Join(", ", inexistentes)}.");
        var inactivo = productos.Values.FirstOrDefault(p => !p.Activo);
        if (inactivo is not null)
            throw new BusinessRuleException($"El producto '{inactivo.Nombre}' ya no está disponible para la venta.");

        // Descuento atómico: UPDATE ... SET Stock = Stock - @cantidad WHERE Id = @id AND Stock >= @cantidad.
        // La condición y la resta ocurren en la misma sentencia con bloqueo de fila, así que dos pedidos
        // simultáneos por la última unidad no pueden pasar ambos: el segundo afecta 0 filas.
        // Se recorre en orden de id para que pedidos concurrentes bloqueen filas en el mismo orden (sin deadlocks).
        foreach (var linea in lineas.OrderBy(l => l.ProductoId))
        {
            if (!await Existencias.DescontarAsync(_db, linea.ProductoId, linea.Cantidad, exigirActivo: true, ct))
            {
                var producto = productos[linea.ProductoId];
                throw new BusinessRuleException(
                    $"Stock insuficiente para '{producto.Nombre}': solicitado {linea.Cantidad}, disponible {producto.Stock}.");
            }
        }

        // El costo se lee después de descontar: las filas ya están bloqueadas por esta transacción.
        var costos = await _db.Productos.AsNoTracking()
            .Where(p => ids.Contains(p.Id))
            .ToDictionaryAsync(p => p.Id, p => p.CostoPromedio, ct);

        // Precio y total siempre salen de la base de datos, nunca del cliente.
        var ahora = _time.GetUtcNow().UtcDateTime;
        var pedido = new Pedido
        {
            UsuarioId = usuarioId,
            ClienteId = cliente.Id,
            Fecha = ahora,
            FormaPago = formaPago,
            Autorizacion = Guid.NewGuid(),
            Detalles = lineas.Select(l =>
            {
                var precio = productos[l.ProductoId].Precio;
                return new PedidoDetalle
                {
                    ProductoId = l.ProductoId,
                    Cantidad = l.Cantidad,
                    PrecioUnitario = precio,
                    Subtotal = precio * l.Cantidad,
                    CostoUnitario = Math.Round(costos[l.ProductoId], 4)
                };
            }).ToList()
        };
        pedido.Total = pedido.Detalles.Sum(d => d.Subtotal);
        (pedido.BaseImponible, pedido.Iva) = Montos.SepararIva(pedido.Total, Pedido.TasaIva);
        pedido.Costo = pedido.Detalles.Sum(d => Montos.Redondear(d.Cantidad * d.CostoUnitario));

        _db.Pedidos.Add(pedido);
        await _db.SaveChangesAsync(ct); // asigna el número de factura

        var factura = $"Factura {Pedido.SerieFactura}-{pedido.Id}";
        foreach (var d in pedido.Detalles.OrderBy(d => d.ProductoId))
            await Existencias.RegistrarMovimientoAsync(_db, d.ProductoId, TiposMovimiento.Venta, -d.Cantidad,
                d.CostoUnitario, factura, usuarioId, ahora, ct);

        var cuentaCobro = formaPago == FormasPago.Efectivo ? CuentasSistema.Caja : CuentasSistema.Bancos;
        await _contabilidad.RegistrarAutomaticaAsync(OrigenesPartida.Venta, pedido.Id,
            $"{factura} a {cliente.Nombre} ({Nit.Formatear(cliente.Nit)}), {formaPago.ToLowerInvariant()}", usuarioId,
            new[]
            {
                LineaAsiento.Cargo(cuentaCobro, pedido.Total),
                LineaAsiento.Abono(CuentasSistema.Ventas, pedido.BaseImponible),
                LineaAsiento.Abono(CuentasSistema.IvaPorPagar, pedido.Iva),
                LineaAsiento.Cargo(CuentasSistema.CostoVentas, pedido.Costo),
                LineaAsiento.Abono(CuentasSistema.Inventario, pedido.Costo)
            }, ct);

        await _db.SaveChangesAsync(ct);
        await tx.CommitAsync(ct);

        return (await ObtenerAsync(pedido.Id, usuarioId, veTodas: true, ct))!;
    }

    /// <summary>
    /// Devuelve la venta solo si la hizo el usuario o si puede ver todas (ADMIN, CONTADOR). Para una ajena
    /// devuelve null (404), así no se revela si ese número existe.
    /// </summary>
    public async Task<PedidoResponse?> ObtenerAsync(int pedidoId, int usuarioId, bool veTodas, CancellationToken ct = default)
    {
        var pedido = await _db.Pedidos.AsNoTracking()
            .Include(p => p.Detalles).ThenInclude(d => d.Producto)
            .Include(p => p.Cliente)
            .FirstOrDefaultAsync(p => p.Id == pedidoId && (veTodas || p.UsuarioId == usuarioId), ct);
        if (pedido is null)
            return null;

        var vendedor = await _db.Usuarios.AsNoTracking()
            .Where(u => u.Id == pedido.UsuarioId).Select(u => u.Username).FirstAsync(ct);
        return MapearRespuesta(pedido, vendedor);
    }

    public async Task<List<VentaResumenResponse>> ListarAsync(int usuarioId, bool veTodas, DateOnly desde, DateOnly hasta,
        CancellationToken ct = default)
    {
        var (inicio, fin) = Calendario.RangoUtc(desde, hasta);
        return await _db.Pedidos.AsNoTracking()
            .Where(p => p.Fecha >= inicio && p.Fecha < fin && (veTodas || p.UsuarioId == usuarioId))
            .OrderByDescending(p => p.Id)
            .Take(1000)
            .Join(_db.Usuarios, p => p.UsuarioId, u => u.Id, (p, u) => new VentaResumenResponse(
                p.Id, Pedido.SerieFactura, p.Fecha, p.Cliente!.Nit, p.Cliente.Nombre, u.Username, p.FormaPago,
                p.Detalles.Count, p.Total))
            .ToListAsync(ct);
    }

    private async Task<Cliente> ClienteDeLaVentaAsync(int? clienteId, CancellationToken ct)
    {
        var cliente = clienteId is { } id
            ? await _db.Clientes.AsNoTracking().FirstOrDefaultAsync(c => c.Id == id, ct)
            : await _db.Clientes.AsNoTracking().FirstOrDefaultAsync(c => c.Nit == Cliente.NitConsumidorFinal, ct);
        if (cliente is null)
            throw new BusinessRuleException(clienteId is null ? "No está configurado el cliente Consumidor Final." : "El cliente no existe.");
        if (!cliente.Activo)
            throw new BusinessRuleException($"El cliente '{cliente.Nombre}' está inactivo.");
        return cliente;
    }

    private static List<LineaPedidoRequest> ValidarLineas(List<LineaPedidoRequest>? lineas)
    {
        if (lineas is null || lineas.Count == 0)
            throw new BusinessRuleException("El pedido debe tener al menos una línea.");

        if (lineas.Count > InputLimits.LineasPorPedidoMax)
            throw new BusinessRuleException($"Un pedido admite como máximo {InputLimits.LineasPorPedidoMax} productos distintos.");

        var cantidadExcesiva = lineas.FirstOrDefault(l => l.Cantidad > InputLimits.CantidadPorLineaMax);
        if (cantidadExcesiva is not null)
            throw new BusinessRuleException(
                $"La cantidad del producto {cantidadExcesiva.ProductoId} supera el máximo de {InputLimits.CantidadPorLineaMax} unidades por línea.");

        var cantidadInvalida = lineas.FirstOrDefault(l => l.Cantidad <= 0);
        if (cantidadInvalida is not null)
            throw new BusinessRuleException(
                $"La cantidad del producto {cantidadInvalida.ProductoId} debe ser mayor que cero.");

        var duplicado = lineas.GroupBy(l => l.ProductoId).FirstOrDefault(g => g.Count() > 1);
        if (duplicado is not null)
            throw new BusinessRuleException(
                $"El producto {duplicado.Key} aparece más de una vez en el pedido. Agrupe las cantidades en una sola línea.");

        return lineas;
    }

    private static PedidoResponse MapearRespuesta(Pedido pedido, string vendedor) =>
        new(
            pedido.Id,
            pedido.Fecha,
            pedido.UsuarioId,
            pedido.Total,
            pedido.Detalles
                .OrderBy(d => d.ProductoId)
                .Select(d => new PedidoLineaResponse(
                    d.ProductoId,
                    d.Producto!.Codigo,
                    d.Producto.Nombre,
                    d.Cantidad,
                    d.PrecioUnitario,
                    d.Subtotal))
                .ToList(),
            Pedido.SerieFactura,
            pedido.Autorizacion,
            pedido.ClienteId,
            Nit.Formatear(pedido.Cliente!.Nit),
            pedido.Cliente.Nombre,
            pedido.Cliente.Direccion,
            vendedor,
            pedido.FormaPago,
            pedido.BaseImponible,
            pedido.Iva);
}
