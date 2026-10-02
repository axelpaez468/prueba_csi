using Microsoft.EntityFrameworkCore;
using Pedidos.Api.Data;
using Pedidos.Api.Domain;

namespace Pedidos.Api.Services.Erp;

/// <summary>
/// Entradas y salidas de mercadería. Cada cambio de existencia es un UPDATE atómico con su condición,
/// así dos operaciones simultáneas sobre el mismo producto no pueden dejar un saldo o un costo incorrecto.
/// Se usa siempre dentro de la transacción de la operación (venta, recepción de compra o ajuste).
/// </summary>
public static class Existencias
{
    /// <summary>UPDATE ... SET Stock = Stock - @q WHERE Id = @id AND Stock >= @q. false si no alcanza.</summary>
    public static async Task<bool> DescontarAsync(AppDbContext db, int productoId, int cantidad, bool exigirActivo, CancellationToken ct) =>
        await db.Productos
            .Where(p => p.Id == productoId && p.Stock >= cantidad && (!exigirActivo || p.Activo))
            .ExecuteUpdateAsync(s => s.SetProperty(p => p.Stock, p => p.Stock - cantidad), ct) == 1;

    /// <summary>
    /// Suma la entrada y recalcula el costo promedio ponderado en la misma sentencia:
    /// nuevo costo = (existencia × costo actual + cantidad × costo de entrada) / (existencia + cantidad).
    /// En un UPDATE, todas las expresiones usan los valores anteriores de la fila.
    /// </summary>
    public static async Task IngresarAsync(AppDbContext db, int productoId, int cantidad, decimal costoUnitario, CancellationToken ct)
    {
        var afectadas = await db.Productos
            .Where(p => p.Id == productoId)
            .ExecuteUpdateAsync(s => s
                .SetProperty(p => p.CostoPromedio,
                    p => (p.Stock * p.CostoPromedio + cantidad * costoUnitario) / (p.Stock + cantidad))
                .SetProperty(p => p.Stock, p => p.Stock + cantidad), ct);
        if (afectadas != 1)
            throw new InvalidOperationException($"No existe el producto {productoId}.");
    }

    /// <summary>
    /// Registra el movimiento de kardex con el saldo y el costo que quedaron. Se lee después del UPDATE:
    /// la fila sigue bloqueada por la transacción, así que el saldo leído es exactamente el de este movimiento.
    /// </summary>
    public static async Task<MovimientoInventario> RegistrarMovimientoAsync(AppDbContext db, int productoId, string tipo,
        int cantidad, decimal costoUnitario, string referencia, int? usuarioId, DateTime fecha, CancellationToken ct)
    {
        var actual = await db.Productos.AsNoTracking()
            .Where(p => p.Id == productoId)
            .Select(p => new { p.Stock, p.CostoPromedio })
            .SingleAsync(ct);

        var movimiento = new MovimientoInventario
        {
            ProductoId = productoId,
            Fecha = fecha,
            Tipo = tipo,
            Cantidad = cantidad,
            CostoUnitario = Math.Round(costoUnitario, 4),
            Saldo = actual.Stock,
            CostoPromedio = Math.Round(actual.CostoPromedio, 4),
            Referencia = referencia.Length > 120 ? referencia[..120] : referencia,
            UsuarioId = usuarioId
        };
        db.MovimientosInventario.Add(movimiento);
        return movimiento;
    }
}
