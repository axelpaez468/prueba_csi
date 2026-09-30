using System.Text.RegularExpressions;
using Microsoft.EntityFrameworkCore;
using Pedidos.Api.Data;
using Pedidos.Api.Domain;
using Pedidos.Api.Dtos;
using Pedidos.Api.Errors;
using Pedidos.Api.Services.Seguridad;

namespace Pedidos.Api.Services.Usuarios;

/// <summary>
/// Administración de usuarios (solo ADMIN). Reglas clave:
/// el administrador no conoce contraseñas (el usuario la define desde una invitación por correo);
/// no se puede desactivar/eliminar a sí mismo ni dejar el sistema sin administradores activos;
/// un usuario con pedidos no se elimina, se desactiva (se conserva el historial).
/// </summary>
public partial class UsuarioService
{
    public const string PrefijoTelefono = "+502";

    private readonly AppDbContext _db;
    private readonly RecuperacionService _recuperacion;
    private readonly BitacoraService _bitacora;
    private readonly TimeProvider _time;

    public UsuarioService(AppDbContext db, RecuperacionService recuperacion, BitacoraService bitacora, TimeProvider time)
    {
        _db = db;
        _recuperacion = recuperacion;
        _bitacora = bitacora;
        _time = time;
    }

    // Nombres: letras (con tildes y ñ), espacios, apóstrofo, punto y guion.
    [GeneratedRegex(@"^\p{L}[\p{L}' .\-]{1,59}$")]
    private static partial Regex RegexNombre();

    [GeneratedRegex(@"^[^@\s]+@[^@\s]+\.[^@\s]{2,}$")]
    private static partial Regex RegexEmail();

    // Guatemala: 8 dígitos; fijos empiezan con 2, 6 o 7 y móviles con 3, 4 o 5.
    [GeneratedRegex(@"^[2-7]\d{7}$")]
    private static partial Regex RegexTelefonoGt();

    [GeneratedRegex(@"^[A-Z0-9][A-Z0-9\-]{2,19}$")]
    private static partial Regex RegexCodigo();

    /// <summary>Acepta "5555 0101", "55550101", "+502 5555-0101" o "50255550101" y devuelve "+50255550101".</summary>
    public static string? NormalizarTelefono(string? telefono)
    {
        var digitos = new string((telefono ?? "").Where(char.IsDigit).ToArray());
        if (digitos.Length == 11 && digitos.StartsWith("502")) digitos = digitos[3..];
        return RegexTelefonoGt().IsMatch(digitos) ? PrefijoTelefono + digitos : null;
    }

    public static UsuarioResponse Mapear(Usuario u) => new(
        u.Id, u.Nombre, u.Apellido, u.Username, u.Email, u.Telefono ?? "", u.CodigoCorporativo, u.Rol, u.Activo,
        u.DosFactor, TieneContrasena: !u.PasswordHash.StartsWith(MarcaSinContrasena), u.CreadoEn);

    /// <summary>Prefijo del hash de un usuario invitado que aún no definió su contraseña (ningún texto lo verifica).</summary>
    private const string MarcaSinContrasena = "!sin-contrasena!";

    // ---------- Consultas ----------

    public async Task<List<UsuarioResponse>> ListarAsync(string? buscar, CancellationToken ct)
    {
        var q = _db.Usuarios.AsNoTracking();
        if (!string.IsNullOrWhiteSpace(buscar))
        {
            var t = buscar.Trim().ToLower();
            q = q.Where(u => u.Username.ToLower().Contains(t) || u.Email.Contains(t) || u.CodigoCorporativo.ToLower().Contains(t));
        }
        var usuarios = await q.OrderBy(u => u.Apellido).ThenBy(u => u.Nombre).Take(500).ToListAsync(ct);
        return usuarios.Select(Mapear).ToList();
    }

    public async Task<UsuarioResponse?> ObtenerAsync(int id, CancellationToken ct)
    {
        var u = await _db.Usuarios.AsNoTracking().FirstOrDefaultAsync(x => x.Id == id, ct);
        return u is null ? null : Mapear(u);
    }

    // ---------- Alta y edición ----------

    public async Task<UsuarioResponse> CrearAsync(GuardarUsuarioRequest r, int adminId, ContextoCliente ctx, CancellationToken ct)
    {
        var datos = await ValidarAsync(r, idExistente: null, ct);
        var usuario = new Usuario
        {
            Nombre = datos.Nombre,
            Apellido = datos.Apellido,
            Username = $"{datos.Nombre} {datos.Apellido}",
            Email = datos.Email,
            Telefono = datos.Telefono,
            CodigoCorporativo = datos.Codigo,
            Rol = datos.Rol,
            // Sin contraseña utilizable hasta que el usuario la cree desde la invitación.
            PasswordHash = MarcaSinContrasena + Guid.NewGuid().ToString("N"),
            // Sin 2FA al crearse: si es administrador, el login le exige configurar Google Authenticator al entrar.
            DosFactor = MetodosDosFactor.Ninguno,
            CreadoEn = _time.GetUtcNow().UtcDateTime
        };
        _db.Usuarios.Add(usuario);
        await _db.SaveChangesAsync(ct);

        await _recuperacion.EnviarInvitacionAsync(usuario, ctx, ct);
        await RegistrarAsync(EventosBitacora.UsuarioCreado, adminId, usuario, ctx, ct);
        return Mapear(usuario);
    }

    public async Task<UsuarioResponse> EditarAsync(int id, GuardarUsuarioRequest r, int adminId, ContextoCliente ctx,
        CancellationToken ct)
    {
        var usuario = await CargarAsync(id, ct);
        var datos = await ValidarAsync(r, id, ct);

        if (usuario.Rol == Roles.Admin && datos.Rol != Roles.Admin)
        {
            if (id == adminId)
                throw new BusinessRuleException("No puedes quitarte el rol de administrador a ti mismo.");
            await ExigirOtroAdminActivoAsync(id, ct);
        }

        var cambiosSensibles = usuario.Email != datos.Email || usuario.Rol != datos.Rol;
        var cambios = new List<string>();
        void Cambio(string campo, string antes, string despues)
        {
            if (antes != despues) cambios.Add(campo);
        }
        Cambio("nombre", usuario.Nombre, datos.Nombre);
        Cambio("apellido", usuario.Apellido, datos.Apellido);
        Cambio("correo", usuario.Email, datos.Email);
        Cambio("teléfono", usuario.Telefono ?? "", datos.Telefono);
        Cambio("código", usuario.CodigoCorporativo, datos.Codigo);
        Cambio("rol", usuario.Rol, datos.Rol);

        usuario.Nombre = datos.Nombre;
        usuario.Apellido = datos.Apellido;
        usuario.Username = $"{datos.Nombre} {datos.Apellido}";
        usuario.Email = datos.Email;
        usuario.Telefono = datos.Telefono;
        usuario.CodigoCorporativo = datos.Codigo;
        usuario.Rol = datos.Rol;

        // Cambiar correo o rol cierra sus sesiones: el token lleva ambos datos y debe volver a emitirse.
        // Si fue promovido a administrador, en su próximo ingreso deberá configurar Google Authenticator.
        if (cambiosSensibles)
            usuario.VersionSesion++;

        await _db.SaveChangesAsync(ct);
        await RegistrarAsync(EventosBitacora.UsuarioEditado, adminId, usuario, ctx, ct,
            cambios.Count == 0 ? "sin cambios" : "cambió: " + string.Join(", ", cambios));
        return Mapear(usuario);
    }

    // ---------- Estado, invitación y eliminación ----------

    public async Task<UsuarioResponse> CambiarEstadoAsync(int id, bool activo, int adminId, ContextoCliente ctx, CancellationToken ct)
    {
        var usuario = await CargarAsync(id, ct);
        if (!activo)
        {
            if (id == adminId)
                throw new BusinessRuleException("No puedes desactivar tu propia cuenta.");
            if (usuario.Rol == Roles.Admin)
                await ExigirOtroAdminActivoAsync(id, ct);
        }
        if (usuario.Activo == activo) return Mapear(usuario);

        usuario.Activo = activo;
        if (!activo)
        {
            usuario.VersionSesion++; // pierde el acceso de inmediato, aunque tenga una sesión abierta
            await _db.DispositivosConfiables.Where(d => d.UsuarioId == id).ExecuteDeleteAsync(ct);
        }
        await _db.SaveChangesAsync(ct);
        await RegistrarAsync(activo ? EventosBitacora.UsuarioActivado : EventosBitacora.UsuarioDesactivado, adminId, usuario, ctx, ct);
        return Mapear(usuario);
    }

    public async Task ReenviarInvitacionAsync(int id, int adminId, ContextoCliente ctx, CancellationToken ct)
    {
        var usuario = await CargarAsync(id, ct);
        if (!usuario.Activo)
            throw new BusinessRuleException("El usuario está desactivado. Actívalo antes de enviarle la invitación.");
        await _recuperacion.EnviarInvitacionAsync(usuario, ctx, ct);
        await RegistrarAsync(EventosBitacora.InvitacionEnviada, adminId, usuario, ctx, ct);
    }

    public async Task EliminarAsync(int id, int adminId, ContextoCliente ctx, CancellationToken ct)
    {
        var usuario = await CargarAsync(id, ct);
        if (id == adminId)
            throw new BusinessRuleException("No puedes eliminar tu propia cuenta.");
        if (usuario.Rol == Roles.Admin)
            await ExigirOtroAdminActivoAsync(id, ct);
        if (await _db.Pedidos.AnyAsync(p => p.UsuarioId == id, ct))
            throw new BusinessRuleException(
                "El usuario tiene pedidos registrados y no se puede eliminar. Desactívalo para quitarle el acceso.");

        var descripcion = Describir(usuario);
        _db.Usuarios.Remove(usuario); // códigos, tokens y dispositivos se borran en cascada
        await _db.SaveChangesAsync(ct);
        await RegistrarAsync(EventosBitacora.UsuarioEliminado, adminId, null, ctx, ct, descripcion);
    }

    // ---------- Auxiliares ----------

    private sealed record DatosValidados(string Nombre, string Apellido, string Email, string Telefono, string Codigo, string Rol);

    private async Task<DatosValidados> ValidarAsync(GuardarUsuarioRequest r, int? idExistente, CancellationToken ct)
    {
        var nombre = Limpiar(r.Nombre);
        var apellido = Limpiar(r.Apellido);
        var email = (r.Email ?? "").Trim().ToLowerInvariant();
        var codigo = (r.CodigoCorporativo ?? "").Trim().ToUpperInvariant();
        var rol = (r.Rol ?? "").Trim().ToUpperInvariant();
        var telefono = NormalizarTelefono(r.Telefono);

        if (!RegexNombre().IsMatch(nombre))
            throw new BusinessRuleException("El nombre es obligatorio (2 a 60 letras).");
        if (!RegexNombre().IsMatch(apellido))
            throw new BusinessRuleException("El apellido es obligatorio (2 a 60 letras).");
        if (email.Length > 254 || !RegexEmail().IsMatch(email))
            throw new BusinessRuleException("Ingresa un correo electrónico válido.");
        if (telefono is null)
            throw new BusinessRuleException("El teléfono debe tener 8 dígitos de Guatemala (se antepone +502), por ejemplo 5555 0101.");
        if (!RegexCodigo().IsMatch(codigo))
            throw new BusinessRuleException("El código corporativo debe tener de 3 a 20 letras, números o guiones (p. ej. VEN-0002).");
        if (rol != Roles.Vendedor && rol != Roles.Admin)
            throw new BusinessRuleException("El rol debe ser VENDEDOR o ADMIN.");

        if (await _db.Usuarios.AnyAsync(u => u.Email == email && u.Id != idExistente, ct))
            throw new BusinessRuleException("Ya existe un usuario con ese correo.");
        if (await _db.Usuarios.AnyAsync(u => u.CodigoCorporativo == codigo && u.Id != idExistente, ct))
            throw new BusinessRuleException("Ya existe un usuario con ese código corporativo.");

        return new DatosValidados(nombre, apellido, email, telefono, codigo, rol);
    }

    /// <summary>Quita espacios de más y caracteres de control.</summary>
    private static string Limpiar(string? s) =>
        string.Join(' ', new string((s ?? "").Where(c => !char.IsControl(c)).ToArray())
            .Split(' ', StringSplitOptions.RemoveEmptyEntries));

    private async Task<Usuario> CargarAsync(int id, CancellationToken ct) =>
        await _db.Usuarios.FirstOrDefaultAsync(u => u.Id == id, ct)
        ?? throw new NoEncontradoException("Usuario no encontrado.");

    private async Task ExigirOtroAdminActivoAsync(int excepto, CancellationToken ct)
    {
        if (!await _db.Usuarios.AnyAsync(u => u.Rol == Roles.Admin && u.Activo && u.Id != excepto, ct))
            throw new BusinessRuleException("Debe quedar al menos un administrador activo en el sistema.");
    }

    private static string Describir(Usuario u) => $"{u.Username} <{u.Email}> ({u.CodigoCorporativo})";

    private async Task RegistrarAsync(string evento, int adminId, Usuario? afectado, ContextoCliente ctx, CancellationToken ct,
        string? detalle = null)
    {
        var admin = await _db.Usuarios.AsNoTracking().Where(u => u.Id == adminId).Select(u => u.Email).FirstOrDefaultAsync(ct);
        var texto = afectado is null ? detalle : detalle is null ? Describir(afectado) : $"{Describir(afectado)}; {detalle}";
        _bitacora.Registrar(evento, true, admin ?? "(desconocido)", ctx, adminId, texto);
        await _db.SaveChangesAsync(ct);
    }
}
