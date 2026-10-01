using Microsoft.EntityFrameworkCore;
using Pedidos.Api.Data;
using Pedidos.Api.Domain;
using Pedidos.Api.Dtos;
using Pedidos.Api.Errors;

namespace Pedidos.Api.Services.Erp;

/// <summary>
/// Pipeline de ventas: Nuevo → Revisado → Autorizado → Despachado → En camino → Entregado/cobrado.
/// Cada paso lo da el rol que corresponde (ver <see cref="EstadosVenta.QuienPuedeLlevarA"/>) y queda en el historial.
/// </summary>
public class PipelineService
{
    /// <summary>Cuántos días se siguen mostrando en el tablero las ventas ya entregadas.</summary>
    public const int DiasEntregadasVisibles = 7;

    private readonly AppDbContext _db;
    private readonly TimeProvider _time;

    public PipelineService(AppDbContext db, TimeProvider time)
    {
        _db = db;
        _time = time;
    }

    /// <summary>El vendedor ve solo sus ventas; los demás roles del pipeline, todas.</summary>
    public static bool VeTodas(string rol) => rol != Roles.Vendedor;

    public async Task<List<TarjetaPipelineResponse>> TableroAsync(int usuarioId, string rol, CancellationToken ct)
    {
        var desdeEntregadas = _time.GetUtcNow().UtcDateTime.AddDays(-DiasEntregadasVisibles);
        var veTodas = VeTodas(rol);
        var filas = await _db.Pedidos.AsNoTracking()
            .Where(p => (veTodas || p.UsuarioId == usuarioId)
                        && (p.Estado != EstadosVenta.Entregado || p.EstadoDesde >= desdeEntregadas))
            .OrderBy(p => p.EstadoDesde)
            .Take(600)
            .Join(_db.Usuarios, p => p.UsuarioId, u => u.Id, (p, u) => new
            {
                p.Id, p.Fecha, Cliente = p.Cliente!.Nombre, Vendedor = u.Username, p.Total, Productos = p.Detalles.Count,
                p.Departamento, p.Municipio, p.Estado, p.EstadoDesde, p.UsuarioId
            })
            .ToListAsync(ct);

        return filas.Select(f => new TarjetaPipelineResponse(f.Id, f.Fecha, f.Cliente, f.Vendedor, f.Total, f.Productos,
                f.Departamento, f.Municipio, f.Estado, f.EstadoDesde,
                PuedeAvanzar(f.Estado, rol, f.UsuarioId == usuarioId)))
            .ToList();
    }

    /// <summary>Lleva la venta a la siguiente etapa. El cambio es condicional: si dos personas la avanzan a la vez, solo una lo logra.</summary>
    public async Task<string> AvanzarAsync(int pedidoId, int usuarioId, string rol, string? nota, CancellationToken ct)
    {
        var venta = await _db.Pedidos.AsNoTracking()
            .Where(p => p.Id == pedidoId && (VeTodas(rol) || p.UsuarioId == usuarioId))
            .Select(p => new { p.Estado, p.UsuarioId })
            .FirstOrDefaultAsync(ct)
            ?? throw new NoEncontradoException("Venta no encontrada.");

        var siguiente = EstadosVenta.Siguiente(venta.Estado)
                        ?? throw new BusinessRuleException("La venta ya fue entregada y cobrada: no tiene más etapas.");
        if (PuedeAvanzar(venta.Estado, rol, venta.UsuarioId == usuarioId) is null)
            throw new BusinessRuleException(
                $"Tu rol no puede pasar la venta a \"{EstadosVenta.Nombre(siguiente)}\". " +
                $"Lo hace: {string.Join(" o ", EstadosVenta.QuienPuedeLlevarA(siguiente).Select(Roles.Nombre))}.");

        var ahora = _time.GetUtcNow().UtcDateTime;
        await using var tx = await _db.Database.BeginTransactionAsync(ct);
        var cambiada = await _db.Pedidos
            .Where(p => p.Id == pedidoId && p.Estado == venta.Estado)
            .ExecuteUpdateAsync(s => s.SetProperty(p => p.Estado, siguiente).SetProperty(p => p.EstadoDesde, ahora), ct);
        if (cambiada == 0)
            throw new BusinessRuleException("Alguien más actualizó esta venta. Recarga el tablero.");

        _db.PedidoHistorial.Add(new PedidoHistorial
        {
            PedidoId = pedidoId,
            Estado = siguiente,
            Fecha = ahora,
            UsuarioId = usuarioId,
            Nota = Contacto.Opcional(nota, 200, "La nota")
        });
        await _db.SaveChangesAsync(ct);
        await tx.CommitAsync(ct);
        return siguiente;
    }

    /// <summary>La siguiente etapa si el rol puede llevarla ahí (el vendedor solo revisa sus propias ventas).</summary>
    public static string? PuedeAvanzar(string estado, string rol, bool esSuya)
    {
        var siguiente = EstadosVenta.Siguiente(estado);
        if (siguiente is null || !EstadosVenta.QuienPuedeLlevarA(siguiente).Contains(rol)) return null;
        if (rol == Roles.Vendedor && !esSuya) return null;
        return siguiente;
    }
}
