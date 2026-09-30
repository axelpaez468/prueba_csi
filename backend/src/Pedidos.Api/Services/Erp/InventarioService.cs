using System.Text.RegularExpressions;
using Microsoft.EntityFrameworkCore;
using Pedidos.Api.Data;
using Pedidos.Api.Domain;
using Pedidos.Api.Dtos;
using Pedidos.Api.Errors;

namespace Pedidos.Api.Services.Erp;

/// <summary>
/// Productos, kardex y ajustes de inventario. La existencia solo cambia con movimientos (ventas, recepciones
/// de compra y ajustes): al crear un producto su existencia es 0 y no se puede editar a mano.
/// </summary>
public partial class InventarioService
{
    public const int CantidadAjusteMax = 100_000;
    public const decimal PrecioMax = 1_000_000m;

    private readonly AppDbContext _db;
    private readonly ContabilidadService _contabilidad;
    private readonly TimeProvider _time;

    public InventarioService(AppDbContext db, ContabilidadService contabilidad, TimeProvider time)
    {
        _db = db;
        _contabilidad = contabilidad;
        _time = time;
    }

    [GeneratedRegex(@"^[A-Z0-9][A-Z0-9\-]{2,19}$")]
    private static partial Regex RegexCodigo();

    // ---------- Productos ----------

    public async Task<List<ProductoInventarioResponse>> ListarAsync(string? buscar, bool soloBajoMinimo, CancellationToken ct)
    {
        var q = _db.Productos.AsNoTracking();
        var texto = Contacto.Limpiar(buscar);
        if (texto is not null)
            q = q.Where(p => p.Codigo.Contains(texto) || p.Nombre.Contains(texto));
        if (soloBajoMinimo)
            q = q.Where(p => p.Activo && p.StockMinimo > 0 && p.Stock <= p.StockMinimo);
        var productos = await q.OrderBy(p => p.Nombre).Take(1000).ToListAsync(ct);
        return productos.Select(Mapear).ToList();
    }

    public async Task<ProductoInventarioResponse> CrearAsync(GuardarProductoRequest r, CancellationToken ct)
    {
        var codigo = (r.Codigo ?? "").Trim().ToUpperInvariant();
        if (!RegexCodigo().IsMatch(codigo))
            throw new BusinessRuleException("El código debe tener de 3 a 20 letras, números o guiones (p. ej. P-006).");
        if (await _db.Productos.AnyAsync(p => p.Codigo == codigo, ct))
            throw new BusinessRuleException("Ya existe un producto con ese código.");

        var producto = new Producto { Codigo = codigo, Stock = 0, CostoPromedio = 0 };
        Aplicar(producto, r);
        _db.Productos.Add(producto);
        await _db.SaveChangesAsync(ct);
        return Mapear(producto);
    }

    public async Task<ProductoInventarioResponse> EditarAsync(int id, GuardarProductoRequest r, CancellationToken ct)
    {
        var producto = await _db.Productos.FirstOrDefaultAsync(p => p.Id == id, ct)
                       ?? throw new NoEncontradoException("Producto no encontrado.");
        Aplicar(producto, r);
        await _db.SaveChangesAsync(ct);
        return Mapear(producto);
    }

    private static void Aplicar(Producto p, GuardarProductoRequest r)
    {
        if (r.Precio <= 0 || r.Precio > PrecioMax || !Montos.TieneCentavosValidos(r.Precio))
            throw new BusinessRuleException($"El precio debe ser mayor que cero, con máximo dos decimales y hasta {PrecioMax:N0}.");
        if (r.StockMinimo < 0 || r.StockMinimo > CantidadAjusteMax)
            throw new BusinessRuleException("El stock mínimo no es válido.");
        p.Nombre = Contacto.Requerido(r.Nombre, 2, 100, "El nombre del producto");
        p.Precio = r.Precio;
        p.StockMinimo = r.StockMinimo;
        p.Activo = r.Activo ?? p.Activo;
    }

    // ---------- Kardex ----------

    public async Task<KardexResponse> KardexAsync(int productoId, CancellationToken ct)
    {
        var producto = await _db.Productos.AsNoTracking().FirstOrDefaultAsync(p => p.Id == productoId, ct)
                       ?? throw new NoEncontradoException("Producto no encontrado.");

        // Los 500 movimientos más recientes, mostrados en orden cronológico.
        var movimientos = await _db.MovimientosInventario.AsNoTracking()
            .Where(m => m.ProductoId == productoId)
            .OrderByDescending(m => m.Id)
            .Take(500)
            .GroupJoin(_db.Usuarios, m => m.UsuarioId, u => u.Id, (m, u) => new { m, u })
            .SelectMany(x => x.u.DefaultIfEmpty(), (x, u) => new { x.m, Usuario = u == null ? null : u.Username })
            .ToListAsync(ct);

        return new KardexResponse(Mapear(producto), movimientos
            .OrderBy(x => x.m.Id)
            .Select(x => new MovimientoResponse(x.m.Id, x.m.Fecha, x.m.Tipo, x.m.Cantidad, x.m.CostoUnitario, x.m.Saldo,
                x.m.CostoPromedio, x.m.Referencia, x.Usuario))
            .ToList());
    }

    // ---------- Ajustes ----------

    /// <summary>
    /// Entrada o salida por conteo físico, merma, daño, etc. Queda en el kardex y en contabilidad:
    /// una salida es un gasto (faltantes) y una entrada un ingreso (sobrantes), al costo del producto.
    /// </summary>
    public async Task<MovimientoResponse> AjustarAsync(AjusteInventarioRequest r, int usuarioId, CancellationToken ct)
    {
        var tipo = (r.Tipo ?? "").Trim().ToUpperInvariant();
        if (tipo is not ("ENTRADA" or "SALIDA"))
            throw new BusinessRuleException("El tipo de ajuste debe ser ENTRADA o SALIDA.");
        if (r.Cantidad <= 0 || r.Cantidad > CantidadAjusteMax)
            throw new BusinessRuleException($"La cantidad debe estar entre 1 y {CantidadAjusteMax:N0}.");
        var motivo = Contacto.Requerido(r.Motivo, 5, 100, "El motivo del ajuste");

        var producto = await _db.Productos.AsNoTracking().FirstOrDefaultAsync(p => p.Id == r.ProductoId, ct)
                       ?? throw new BusinessRuleException("El producto no existe.");
        var entrada = tipo == "ENTRADA";
        var costoEntrada = r.CostoUnitario ?? producto.CostoPromedio;
        if (entrada && (costoEntrada <= 0 || costoEntrada > PrecioMax))
            throw new BusinessRuleException("Indica el costo unitario sin IVA de la mercadería que entra (mayor que cero).");
        if (r.CostoUnitario is { } costo && !Montos.TieneCentavosValidos(costo))
            throw new BusinessRuleException("El costo unitario admite como máximo dos decimales.");

        var ahora = _time.GetUtcNow().UtcDateTime;
        await using var tx = await _db.Database.BeginTransactionAsync(ct);

        MovimientoInventario movimiento;
        if (entrada)
        {
            await Existencias.IngresarAsync(_db, producto.Id, r.Cantidad, costoEntrada, ct);
            movimiento = await Existencias.RegistrarMovimientoAsync(_db, producto.Id, TiposMovimiento.AjusteEntrada,
                r.Cantidad, costoEntrada, $"Ajuste: {motivo}", usuarioId, ahora, ct);
        }
        else
        {
            if (!await Existencias.DescontarAsync(_db, producto.Id, r.Cantidad, exigirActivo: false, ct))
                throw new BusinessRuleException(
                    $"No hay suficiente existencia de '{producto.Nombre}': quieres sacar {r.Cantidad} y hay {producto.Stock}.");
            movimiento = await Existencias.RegistrarMovimientoAsync(_db, producto.Id, TiposMovimiento.AjusteSalida,
                -r.Cantidad, 0, $"Ajuste: {motivo}", usuarioId, ahora, ct);
            movimiento.CostoUnitario = movimiento.CostoPromedio; // una salida no cambia el costo promedio
        }
        await _db.SaveChangesAsync(ct);

        var monto = Montos.Redondear(r.Cantidad * movimiento.CostoUnitario);
        var concepto = $"Ajuste de inventario {producto.Codigo} ({(entrada ? "entrada" : "salida")} de {r.Cantidad}): {motivo}";
        if (monto > 0)
        {
            await _contabilidad.RegistrarAutomaticaAsync(OrigenesPartida.Ajuste, movimiento.Id, concepto, usuarioId,
                entrada
                    ? new[] { LineaAsiento.Cargo(CuentasSistema.Inventario, monto), LineaAsiento.Abono(CuentasSistema.OtrosIngresos, monto) }
                    : new[] { LineaAsiento.Cargo(CuentasSistema.FaltantesInventario, monto), LineaAsiento.Abono(CuentasSistema.Inventario, monto) },
                ct);
            await _db.SaveChangesAsync(ct);
        }
        await tx.CommitAsync(ct);

        var usuario = await _db.Usuarios.AsNoTracking().Where(u => u.Id == usuarioId).Select(u => u.Username).FirstOrDefaultAsync(ct);
        return new MovimientoResponse(movimiento.Id, movimiento.Fecha, movimiento.Tipo, movimiento.Cantidad,
            movimiento.CostoUnitario, movimiento.Saldo, movimiento.CostoPromedio, movimiento.Referencia, usuario);
    }

    public static ProductoInventarioResponse Mapear(Producto p)
    {
        decimal? margen = null;
        if (p.CostoPromedio > 0 && p.Precio > 0)
        {
            var precioSinIva = p.Precio / (1 + Pedido.TasaIva);
            margen = Math.Round((precioSinIva - p.CostoPromedio) / precioSinIva * 100, 1);
        }
        return new ProductoInventarioResponse(p.Id, p.Codigo, p.Nombre, p.Precio, p.Stock, p.StockMinimo,
            Math.Round(p.CostoPromedio, 4), Montos.Redondear(p.Stock * p.CostoPromedio), p.Activo,
            p.Activo && p.StockMinimo > 0 && p.Stock <= p.StockMinimo, margen);
    }
}
