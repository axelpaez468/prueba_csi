using Microsoft.EntityFrameworkCore;
using Pedidos.Api.Data;
using Pedidos.Api.Domain;
using Pedidos.Api.Dtos;
using Pedidos.Api.Errors;

namespace Pedidos.Api.Services.Erp;

/// <summary>Clientes y proveedores: NIT de Guatemala validado (dígito verificador) y único.</summary>
public class TercerosService
{
    private readonly AppDbContext _db;
    private readonly TimeProvider _time;

    public TercerosService(AppDbContext db, TimeProvider time)
    {
        _db = db;
        _time = time;
    }

    // ---------- Clientes ----------

    public async Task<List<ClienteResponse>> ListarClientesAsync(string? buscar, bool incluirInactivos, CancellationToken ct)
    {
        var q = _db.Clientes.AsNoTracking();
        if (!incluirInactivos) q = q.Where(c => c.Activo);
        var texto = Contacto.Limpiar(buscar);
        if (texto is not null)
        {
            var nit = Nit.Normalizar(texto);
            q = q.Where(c => c.Nit.StartsWith(nit) || c.Nombre.Contains(texto));
        }
        var clientes = await q
            .OrderBy(c => c.Nit == Cliente.NitConsumidorFinal ? 0 : 1).ThenBy(c => c.Nombre)
            .Take(200).ToListAsync(ct);
        return clientes.Select(MapearCliente).ToList();
    }

    public async Task<ClienteResponse> CrearClienteAsync(GuardarClienteRequest r, CancellationToken ct)
    {
        var nit = await ValidarNitAsync(r.Nit, esCliente: true, idExistente: null, ct);
        var cliente = new Cliente { Nit = nit, CreadoEn = _time.GetUtcNow().UtcDateTime };
        AplicarCliente(cliente, r);
        _db.Clientes.Add(cliente);
        await _db.SaveChangesAsync(ct);
        return MapearCliente(cliente);
    }

    public async Task<ClienteResponse> EditarClienteAsync(int id, GuardarClienteRequest r, CancellationToken ct)
    {
        var cliente = await _db.Clientes.FirstOrDefaultAsync(c => c.Id == id, ct)
                      ?? throw new NoEncontradoException("Cliente no encontrado.");
        if (cliente.Nit == Cliente.NitConsumidorFinal)
            throw new BusinessRuleException("El cliente Consumidor Final es del sistema y no se puede modificar.");
        cliente.Nit = await ValidarNitAsync(r.Nit, esCliente: true, idExistente: id, ct);
        AplicarCliente(cliente, r);
        await _db.SaveChangesAsync(ct);
        return MapearCliente(cliente);
    }

    private static void AplicarCliente(Cliente c, GuardarClienteRequest r)
    {
        c.Nombre = Contacto.Requerido(r.Nombre, 2, 150, "El nombre del cliente");
        c.Direccion = Contacto.Opcional(r.Direccion, 200, "La dirección");
        c.Telefono = Contacto.Telefono(r.Telefono);
        c.Email = Contacto.Email(r.Email);
        c.Activo = r.Activo ?? c.Activo;
    }

    public static ClienteResponse MapearCliente(Cliente c) => new(
        c.Id, c.Nit, Nit.Formatear(c.Nit), c.Nombre, c.Direccion, c.Telefono, c.Email, c.Activo,
        c.Nit == Cliente.NitConsumidorFinal);

    // ---------- Proveedores ----------

    public async Task<List<ProveedorResponse>> ListarProveedoresAsync(string? buscar, bool incluirInactivos, CancellationToken ct)
    {
        var q = _db.Proveedores.AsNoTracking();
        if (!incluirInactivos) q = q.Where(p => p.Activo);
        var texto = Contacto.Limpiar(buscar);
        if (texto is not null)
        {
            var nit = Nit.Normalizar(texto);
            q = q.Where(p => p.Nit.StartsWith(nit) || p.Nombre.Contains(texto));
        }
        var proveedores = await q.OrderBy(p => p.Nombre).Take(200).ToListAsync(ct);
        return proveedores.Select(MapearProveedor).ToList();
    }

    public async Task<ProveedorResponse> CrearProveedorAsync(GuardarProveedorRequest r, CancellationToken ct)
    {
        var nit = await ValidarNitAsync(r.Nit, esCliente: false, idExistente: null, ct);
        var proveedor = new Proveedor { Nit = nit, CreadoEn = _time.GetUtcNow().UtcDateTime };
        AplicarProveedor(proveedor, r);
        _db.Proveedores.Add(proveedor);
        await _db.SaveChangesAsync(ct);
        return MapearProveedor(proveedor);
    }

    public async Task<ProveedorResponse> EditarProveedorAsync(int id, GuardarProveedorRequest r, CancellationToken ct)
    {
        var proveedor = await _db.Proveedores.FirstOrDefaultAsync(p => p.Id == id, ct)
                        ?? throw new NoEncontradoException("Proveedor no encontrado.");
        proveedor.Nit = await ValidarNitAsync(r.Nit, esCliente: false, idExistente: id, ct);
        AplicarProveedor(proveedor, r);
        await _db.SaveChangesAsync(ct);
        return MapearProveedor(proveedor);
    }

    private static void AplicarProveedor(Proveedor p, GuardarProveedorRequest r)
    {
        p.Nombre = Contacto.Requerido(r.Nombre, 2, 150, "El nombre del proveedor");
        p.Contacto = Contacto.Opcional(r.Contacto, 100, "El contacto");
        p.Telefono = Contacto.Telefono(r.Telefono);
        p.Email = Contacto.Email(r.Email);
        p.Direccion = Contacto.Opcional(r.Direccion, 200, "La dirección");
        p.Activo = r.Activo ?? p.Activo;
    }

    public static ProveedorResponse MapearProveedor(Proveedor p) => new(
        p.Id, p.Nit, Nit.Formatear(p.Nit), p.Nombre, p.Contacto, p.Telefono, p.Email, p.Direccion, p.Activo);

    // ---------- Auxiliares ----------

    private async Task<string> ValidarNitAsync(string? valor, bool esCliente, int? idExistente, CancellationToken ct)
    {
        var nit = Nit.Normalizar(valor);
        if (nit == Cliente.NitConsumidorFinal)
            throw new BusinessRuleException(esCliente
                ? "Para consumidor final usa el cliente \"CF\" que ya existe."
                : "Un proveedor debe tener NIT.");
        if (!Nit.EsValido(nit))
            throw new BusinessRuleException("El NIT no es válido: revisa los dígitos y el verificador (p. ej. 1234567-9).");

        var repetido = esCliente
            ? await _db.Clientes.AnyAsync(c => c.Nit == nit && c.Id != idExistente, ct)
            : await _db.Proveedores.AnyAsync(p => p.Nit == nit && p.Id != idExistente, ct);
        if (repetido)
            throw new BusinessRuleException($"Ya existe un {(esCliente ? "cliente" : "proveedor")} con el NIT {Nit.Formatear(nit)}.");
        return nit;
    }
}
