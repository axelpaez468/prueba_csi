using Pedidos.Api.Domain;
using Pedidos.Api.Dtos;
using Pedidos.Api.Errors;
using Pedidos.Api.Services.Usuarios;
using Pedidos.Tests.Infra;

namespace Pedidos.Tests;

public class UsuarioServiceTests : IDisposable
{
    private readonly TestDb _testDb = new();
    private readonly ServiciosSeguridad _s = new();

    public void Dispose() => _testDb.Dispose();

    private UsuarioService Servicio() => _s.Usuarios(_testDb.CrearContexto());

    private static GuardarUsuarioRequest Nuevo(
        string email = "ana.lopez@empresa.gt", string codigo = "ven-0100", string rol = "VENDEDOR",
        string telefono = "4123 4567", string nombre = "  Ana   María ", string apellido = "López") =>
        new(nombre, apellido, telefono, email, codigo, rol);

    private Task<UsuarioResponse> Crear(GuardarUsuarioRequest r) =>
        Servicio().CrearAsync(r, TestDb.AdminId, _s.Contexto, default);

    // ---------- Alta ----------

    [Fact]
    public async Task Crear_NormalizaLosDatos_YEnviaLaInvitacion()
    {
        var u = await Crear(Nuevo(email: " Ana.Lopez@Empresa.GT "));

        Assert.Equal("Ana María", u.Nombre);
        Assert.Equal("Ana María López", u.NombreCompleto);
        Assert.Equal("ana.lopez@empresa.gt", u.Email);
        Assert.Equal("+50241234567", u.Telefono);
        Assert.Equal("VEN-0100", u.CodigoCorporativo);
        Assert.True(u.Activo);
        Assert.False(u.TieneContrasena);
        Assert.Contains(_s.Correo.Enviados, m => m.Para == "ana.lopez@empresa.gt" && m.Asunto.Contains("Bienvenido"));
    }

    [Fact]
    public async Task UsuarioInvitado_NoPuedeEntrarHastaCrearSuContrasena_YLuegoSi()
    {
        await Crear(Nuevo());
        var login = await _s.Auth(_testDb.CrearContexto())
            .LoginAsync("ana.lopez@empresa.gt", "cualquier-cosa", null, _s.Contexto, default);
        Assert.Null(login.Sesion);

        await _s.Recuperacion(_testDb.CrearContexto()).RestablecerAsync(
            _s.Correo.UltimoTokenInvitacion("ana.lopez@empresa.gt"), "Mi-Clave-Nueva-2026", _s.Contexto, default);

        var despues = await _s.Auth(_testDb.CrearContexto())
            .LoginAsync("ana.lopez@empresa.gt", "Mi-Clave-Nueva-2026", null, _s.Contexto, default);
        Assert.NotNull(despues.Sesion);
        Assert.Equal("Ana María López", despues.Sesion.Username);
    }

    [Fact]
    public async Task Crear_Administrador_DebeConfigurarGoogleAuthenticatorEnSuPrimerIngreso()
    {
        await Crear(Nuevo(rol: "ADMIN"));
        await _s.Recuperacion(_testDb.CrearContexto()).RestablecerAsync(
            _s.Correo.UltimoTokenInvitacion("ana.lopez@empresa.gt"), "Mi-Clave-Nueva-2026", _s.Contexto, default);

        var login = await _s.Auth(_testDb.CrearContexto())
            .LoginAsync("ana.lopez@empresa.gt", "Mi-Clave-Nueva-2026", null, _s.Contexto, default);

        Assert.Null(login.Sesion);
        Assert.Equal(MetodosDosFactor.Configurar, login.Desafio!.Metodo);
        Assert.Contains(_s.Correo.Enviados, m => m.Texto.Contains("Google Authenticator"));
    }

    [Theory]
    [InlineData("41234567", "+50241234567")]
    [InlineData("4123-4567", "+50241234567")]
    [InlineData("+502 4123 4567", "+50241234567")]
    [InlineData("50241234567", "+50241234567")]
    [InlineData("1234567", null)]     // 7 dígitos
    [InlineData("91234567", null)]    // no empieza con 2-7
    [InlineData("+1 415 555 0101", null)]
    public void NormalizarTelefono_AceptaSoloNumerosDeGuatemala(string entrada, string? esperado)
    {
        Assert.Equal(esperado, UsuarioService.NormalizarTelefono(entrada));
    }

    [Theory]
    [InlineData("A", "López", "ana@empresa.gt", "VEN-0100", "VENDEDOR", "41234567", "nombre")]
    [InlineData("Ana", "L0pez", "ana@empresa.gt", "VEN-0100", "VENDEDOR", "41234567", "apellido")]
    [InlineData("Ana", "López", "ana-sin-arroba", "VEN-0100", "VENDEDOR", "41234567", "correo")]
    [InlineData("Ana", "López", "ana@empresa.gt", "V", "VENDEDOR", "41234567", "código")]
    [InlineData("Ana", "López", "ana@empresa.gt", "VEN-0100", "GERENTE", "41234567", "rol")]
    [InlineData("Ana", "López", "ana@empresa.gt", "VEN-0100", "VENDEDOR", "123", "teléfono")]
    public async Task Crear_ConDatosInvalidos_Falla(string nombre, string apellido, string email, string codigo,
        string rol, string telefono, string campo)
    {
        var ex = await Assert.ThrowsAsync<BusinessRuleException>(() =>
            Crear(new GuardarUsuarioRequest(nombre, apellido, telefono, email, codigo, rol)));

        Assert.Contains(campo, ex.Message, StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public async Task Crear_ConCorreoOCodigoRepetido_Falla()
    {
        await Assert.ThrowsAsync<BusinessRuleException>(() => Crear(Nuevo(email: TestDb.EmailVendedor.ToUpper())));
        await Assert.ThrowsAsync<BusinessRuleException>(() => Crear(Nuevo(codigo: "ven-0001")));
    }

    // ---------- Edición ----------

    [Fact]
    public async Task Editar_ActualizaElNombreParaMostrar_YCambiarElRolCierraSusSesiones()
    {
        var r = new GuardarUsuarioRequest("Carlos", "Pérez", "55550102", TestDb.EmailVendedor, "VEN-0001", "ADMIN");

        var u = await Servicio().EditarAsync(TestDb.VendedorId, r, TestDb.AdminId, _s.Contexto, default);

        Assert.Equal("Carlos Pérez", u.NombreCompleto);
        Assert.Equal(Roles.Admin, u.Rol);
        await using var db = _testDb.CrearContexto();
        Assert.Equal(1, db.Usuarios.Single(x => x.Id == TestDb.VendedorId).VersionSesion);
    }

    [Fact]
    public async Task Editar_NoPermiteQuitarseElRolDeAdminASiMismo()
    {
        var r = new GuardarUsuarioRequest("Admin", "General", "55550101", TestDb.EmailAdmin, "ADM-0001", "VENDEDOR");

        await Assert.ThrowsAsync<BusinessRuleException>(() =>
            Servicio().EditarAsync(TestDb.AdminId, r, TestDb.AdminId, _s.Contexto, default));
    }

    [Fact]
    public async Task Editar_UsuarioInexistente_DevuelveNoEncontrado()
    {
        await Assert.ThrowsAsync<NoEncontradoException>(() =>
            Servicio().EditarAsync(999, Nuevo(), TestDb.AdminId, _s.Contexto, default));
    }

    // ---------- Activar / desactivar / eliminar ----------

    [Fact]
    public async Task Desactivar_BloqueaElLogin_YActivar_LoDevuelve()
    {
        await Servicio().CambiarEstadoAsync(TestDb.VendedorId, false, TestDb.AdminId, _s.Contexto, default);

        var login = await _s.Auth(_testDb.CrearContexto())
            .LoginAsync(TestDb.EmailVendedor, TestDb.PasswordDePrueba, null, _s.Contexto, default);
        Assert.True(login.Desactivada);
        Assert.Null(login.Sesion);
        await using (var db = _testDb.CrearContexto())
            Assert.Equal(1, db.Usuarios.Single(x => x.Id == TestDb.VendedorId).VersionSesion); // sesiones cerradas

        await Servicio().CambiarEstadoAsync(TestDb.VendedorId, true, TestDb.AdminId, _s.Contexto, default);
        Assert.NotNull((await _s.Auth(_testDb.CrearContexto())
            .LoginAsync(TestDb.EmailVendedor, TestDb.PasswordDePrueba, null, _s.Contexto, default)).Sesion);
    }

    [Fact]
    public async Task UsuarioDesactivado_NoRecibeEnlaceDeRecuperacion()
    {
        await Servicio().CambiarEstadoAsync(TestDb.VendedorId, false, TestDb.AdminId, _s.Contexto, default);

        await _s.Recuperacion(_testDb.CrearContexto()).SolicitarAsync(TestDb.EmailVendedor, _s.Contexto, default);

        Assert.DoesNotContain(_s.Correo.Enviados, m => m.Asunto.Contains("Restablece"));
    }

    [Fact]
    public async Task NoSePuedeDesactivarNiEliminarASiMismo()
    {
        await Assert.ThrowsAsync<BusinessRuleException>(() =>
            Servicio().CambiarEstadoAsync(TestDb.AdminId, false, TestDb.AdminId, _s.Contexto, default));
        await Assert.ThrowsAsync<BusinessRuleException>(() =>
            Servicio().EliminarAsync(TestDb.AdminId, TestDb.AdminId, _s.Contexto, default));
    }

    [Fact]
    public async Task NoSePuedeDesactivarAlUltimoAdministradorActivo()
    {
        var otroAdmin = await Crear(Nuevo(rol: "ADMIN"));

        // El otro admin intenta desactivar al original: permitido porque queda él.
        await Servicio().CambiarEstadoAsync(TestDb.AdminId, false, otroAdmin.Id, _s.Contexto, default);
        // Ahora el original (inactivo) no cuenta: no se puede desactivar al único admin activo restante.
        await Assert.ThrowsAsync<BusinessRuleException>(() =>
            Servicio().CambiarEstadoAsync(otroAdmin.Id, false, TestDb.VendedorId, _s.Contexto, default));
    }

    [Fact]
    public async Task Eliminar_UsuarioConPedidos_Falla_YSinPedidos_LoBorra()
    {
        await using (var db = _testDb.CrearContexto())
        {
            db.Pedidos.Add(new Pedido { UsuarioId = TestDb.VendedorId, Fecha = DateTime.UtcNow, Total = 1 });
            await db.SaveChangesAsync();
        }

        var ex = await Assert.ThrowsAsync<BusinessRuleException>(() =>
            Servicio().EliminarAsync(TestDb.VendedorId, TestDb.AdminId, _s.Contexto, default));
        Assert.Contains("Desactívalo", ex.Message);

        await Servicio().EliminarAsync(TestDb.OtroVendedorId, TestDb.AdminId, _s.Contexto, default);
        await using var verificacion = _testDb.CrearContexto();
        Assert.False(verificacion.Usuarios.Any(u => u.Id == TestDb.OtroVendedorId));
        Assert.Contains(verificacion.BitacoraAccesos, r => r.Evento == EventosBitacora.UsuarioEliminado && r.UsuarioId == TestDb.AdminId);
    }

    [Fact]
    public async Task Listar_BuscaPorNombreCorreoOCodigo()
    {
        Assert.Equal(2, (await Servicio().ListarAsync("vendedor", default)).Count);
        Assert.Single(await Servicio().ListarAsync("adm-00", default));
    }
}
