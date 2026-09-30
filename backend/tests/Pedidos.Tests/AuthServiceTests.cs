using System.IdentityModel.Tokens.Jwt;
using Pedidos.Api.Security;
using Pedidos.Tests.Infra;

namespace Pedidos.Tests;

public class AuthServiceTests : IDisposable
{
    private readonly TestDb _testDb = new();
    private readonly ServiciosSeguridad _s = new();

    public void Dispose() => _testDb.Dispose();

    private Task<Pedidos.Api.Services.LoginResultado> Login(string email, string password, string? tokenDispositivo = null) =>
        _s.Auth(_testDb.CrearContexto()).LoginAsync(email, password, tokenDispositivo, _s.Contexto, default);

    [Fact]
    public async Task Login_ConCorreoYContrasenaValidos_DevuelveTokenConRolCorreoYVersionDeSesion()
    {
        var resultado = await Login(TestDb.EmailVendedor, TestDb.PasswordDePrueba);

        Assert.NotNull(resultado.Sesion);
        var token = new JwtSecurityTokenHandler().ReadJwtToken(resultado.Sesion.Token);
        Assert.Equal("VENDEDOR", token.Claims.Single(c => c.Type == JwtClaims.Role).Value);
        Assert.Equal(TestDb.EmailVendedor, token.Claims.Single(c => c.Type == JwtClaims.Email).Value);
        Assert.Equal("0", token.Claims.Single(c => c.Type == JwtClaims.VersionSesion).Value);
        Assert.True(token.ValidTo > DateTime.UtcNow);
    }

    [Fact]
    public async Task Login_IgnoraMayusculasYEspaciosEnElCorreo()
    {
        Assert.NotNull((await Login("  VENDEDOR@Pedidos.TEST ", TestDb.PasswordDePrueba)).Sesion);
    }

    [Theory]
    [InlineData(TestDb.EmailAdmin, "clave-incorrecta")]
    [InlineData("no-existe@pedidos.test", TestDb.PasswordDePrueba)]
    public async Task Login_ConCredencialesInvalidas_NoEmiteToken_YQuedaEnLaBitacora(string email, string password)
    {
        var resultado = await Login(email, password);

        Assert.Null(resultado.Sesion);
        Assert.Null(resultado.Desafio);
        await using var db = _testDb.CrearContexto();
        Assert.Contains(db.BitacoraAccesos, r => r.Email == email && r.Evento == "LOGIN_FALLIDO" && !r.Exito && r.Ip == ServiciosSeguridad.Ip);
    }

    [Theory]
    [InlineData("' OR '1'='1", "' OR '1'='1")]
    [InlineData("admin@pedidos.test' --", "x")]
    [InlineData("x'; DROP TABLE Usuarios; --", "x")]
    [InlineData("' UNION SELECT Id, Email, PasswordHash, Rol FROM Usuarios --", "x")]
    public async Task Login_ConInyeccionSql_NoAutentica_YNoAlteraLaBaseDeDatos(string email, string password)
    {
        var resultado = await Login(email, password);

        Assert.Null(resultado.Sesion);
        await using var db = _testDb.CrearContexto();
        Assert.Equal(3, db.Usuarios.Count());
    }

    [Fact]
    public async Task Login_TrasVariosFallos_BloqueaLaCuentaAunqueLaContrasenaSeaCorrecta()
    {
        for (var i = 0; i < LoginThrottle.FallosPermitidos; i++)
            await Login(TestDb.EmailVendedor, "incorrecta");

        var resultado = await Login(TestDb.EmailVendedor, TestDb.PasswordDePrueba);

        Assert.Null(resultado.Sesion);
        Assert.NotNull(resultado.BloqueadoPor);

        // Pasado el bloqueo vuelve a funcionar.
        _s.Reloj.Advance(LoginThrottle.DuracionBloqueo + TimeSpan.FromSeconds(1));
        Assert.NotNull((await Login(TestDb.EmailVendedor, TestDb.PasswordDePrueba)).Sesion);
    }

    [Fact]
    public async Task Login_DesdeDispositivoNuevo_AvisaPorCorreoSoloLaPrimeraVez()
    {
        await Login(TestDb.EmailVendedor, TestDb.PasswordDePrueba);
        await Login(TestDb.EmailVendedor, TestDb.PasswordDePrueba);

        var avisos = _s.Correo.Enviados.Where(m => m.Para == TestDb.EmailVendedor && m.Asunto.Contains("Nuevo inicio")).ToList();
        Assert.Single(avisos);
        Assert.Contains("Chrome en Windows", avisos[0].Texto);
    }

    [Fact]
    public void JwtOptions_ConClaveCorta_FallaAlValidar()
    {
        Assert.Throws<InvalidOperationException>(() => new JwtOptions { Key = "clave-secreta" }.Validar());
    }

    [Fact]
    public void SeguridadOptions_SinClaveMaestraDe32Bytes_FallaAlValidar()
    {
        Assert.Throws<InvalidOperationException>(() => new SeguridadOptions { ClaveMaestra = "corta" }.Validar());
    }
}
