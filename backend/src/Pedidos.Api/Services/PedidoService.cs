using Microsoft.EntityFrameworkCore;
using Pedidos.Api.Data;
using Pedidos.Api.Domain;
using Pedidos.Api.Dtos;
using Pedidos.Api.Errors;

namespace Pedidos.Api.Services;

public class PedidoService
{
    private readonly AppDbContext _db;
    private readonly TimeProvider _time;

    public PedidoService(AppDbContext db, TimeProvider time)
    {
        _db = db;
        _time = time;
    }

    public async Task<PedidoResponse> CrearAsync(int usuarioId, CrearPedidoRequest request, CancellationToken ct = default)
    {
        var lineas = ValidarLineas(request.Lineas);
        var ids = lineas.Select(l => l.ProductoId).ToList();

        // Cabecera, detalle y descuento de stock en una sola transacción:
        // si algo falla antes del Commit, el Dispose hace rollback de todo.
        await using var tx = await _db.Database.BeginTransactionAsync(ct);

        var productos = await _db.Productos.AsNoTracking()
            .Where(p => ids.Contains(p.Id))
            .ToDictionaryAsync(p => p.Id, ct);

        var inexistentes = ids.Where(id => !productos.ContainsKey(id)).ToList();
        if (inexistentes.Count > 0)
            throw new BusinessRuleException($"No existe el producto con id: {string.Join(", ", inexistentes)}.");

        // Descuento atómico: UPDATE ... SET Stock = Stock - @cantidad WHERE Id = @id AND Stock >= @cantidad.
        // La condición y la resta ocurren en la misma sentencia con bloqueo de fila, así que dos pedidos
        // simultáneos por la última unidad no pueden pasar ambos: el segundo afecta 0 filas.
        // Se recorre en orden de id para que pedidos concurrentes bloqueen filas en el mismo orden (sin deadlocks).
        foreach (var linea in lineas.OrderBy(l => l.ProductoId))
        {
            var afectadas = await _db.Productos
                .Where(p => p.Id == linea.ProductoId && p.Stock >= linea.Cantidad)
                .ExecuteUpdateAsync(s => s.SetProperty(p => p.Stock, p => p.Stock - linea.Cantidad), ct);

            if (afectadas == 0)
            {
                var producto = productos[linea.ProductoId];
                throw new BusinessRuleException(
                    $"Stock insuficiente para '{producto.Nombre}': solicitado {linea.Cantidad}, disponible {producto.Stock}.");
            }
        }

        // Precio y total siempre salen de la base de datos, nunca del cliente.
        var pedido = new Pedido
        {
            UsuarioId = usuarioId,
            Fecha = _time.GetUtcNow().UtcDateTime,
            Detalles = lineas.Select(l =>
            {
                var precio = productos[l.ProductoId].Precio;
                return new PedidoDetalle
                {
                    ProductoId = l.ProductoId,
                    Cantidad = l.Cantidad,
                    PrecioUnitario = precio,
                    Subtotal = precio * l.Cantidad
                };
            }).ToList()
        };
        pedido.Total = pedido.Detalles.Sum(d => d.Subtotal);

        _db.Pedidos.Add(pedido);
        await _db.SaveChangesAsync(ct);
        await tx.CommitAsync(ct);

        return MapearRespuesta(pedido, productos);
    }

    /// <summary>
    /// Devuelve el pedido solo si pertenece al usuario o si es ADMIN. Para un pedido ajeno devuelve null
    /// (404), así no se revela si ese número de pedido existe.
    /// </summary>
    public async Task<PedidoResponse?> ObtenerAsync(int pedidoId, int usuarioId, bool esAdmin, CancellationToken ct = default)
    {
        var pedido = await _db.Pedidos.AsNoTracking()
            .Include(p => p.Detalles).ThenInclude(d => d.Producto)
            .FirstOrDefaultAsync(p => p.Id == pedidoId && (esAdmin || p.UsuarioId == usuarioId), ct);

        if (pedido is null)
            return null;

        var productos = pedido.Detalles.ToDictionary(d => d.ProductoId, d => d.Producto!);
        return MapearRespuesta(pedido, productos);
    }

    private static List<LineaPedidoRequest> ValidarLineas(List<LineaPedidoRequest>? lineas)
    {
        if (lineas is null || lineas.Count == 0)
            throw new BusinessRuleException("El pedido debe tener al menos una línea.");

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

    private static PedidoResponse MapearRespuesta(Pedido pedido, IReadOnlyDictionary<int, Producto> productos) =>
        new(
            pedido.Id,
            pedido.Fecha,
            pedido.UsuarioId,
            pedido.Total,
            pedido.Detalles
                .OrderBy(d => d.ProductoId)
                .Select(d => new PedidoLineaResponse(
                    d.ProductoId,
                    productos[d.ProductoId].Codigo,
                    productos[d.ProductoId].Nombre,
                    d.Cantidad,
                    d.PrecioUnitario,
                    d.Subtotal))
                .ToList());
}
