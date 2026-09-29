using System.IdentityModel.Tokens.Jwt;
using Microsoft.Extensions.Caching.Memory;
using Microsoft.Extensions.Options;
using Pedidos.Api.Security;
using Pedidos.Api.Services;
using Pedidos.Tests.Infra;

namespace Pedidos.Tests;

public class AuthServiceTests : IDisposable
{
    private readonly TestDb _testDb = new();
    private readonly LoginThrottle _throttle =
        new(new MemoryCache(new MemoryCacheOptions { SizeLimit = 1000 }), TimeProvider.System);

    public void Dispose() => _testDb.Dispose();

    private AuthService CrearServicio()
    {
        var options = Options.Create(new JwtOptions { Key = new string('k', JwtOptions.MinKeyBytes) });
        return new AuthService(_testDb.CrearContexto(), new TokenService(options, TimeProvider.System), _throttle);
    }

    [Fact]
    public async Task Login_ConCredencialesValidas_DevuelveTokenConRolYExpiracion()
    {
        var resultado = await CrearServicio().LoginAsync("admin", TestDb.PasswordDePrueba, default);

        Assert.NotNull(resultado.Sesion);
        var token = new JwtSecurityTokenHandler().ReadJwtToken(resultado.Sesion.Token);
        Assert.Equal("ADMIN", token.Claims.Single(c => c.Type == JwtClaims.Role).Value);
        Assert.Equal(TestDb.AdminId.ToString(), token.Claims.Single(c => c.Type == JwtClaims.UserId).Value);
        Assert.True(token.ValidTo > DateTime.UtcNow);
    }

    [Theory]
    [InlineData("admin", "clave-incorrecta")]
    [InlineData("no-existe", TestDb.PasswordDePrueba)]
    public async Task Login_ConCredencialesInvalidas_NoEmiteToken(string usuario, string password)
    {
        var resultado = await CrearServicio().LoginAsync(usuario, password, default);

        Assert.Null(resultado.Sesion);
        Assert.Null(resultado.BloqueadoPor);
    }

    [Theory]
    [InlineData("' OR '1'='1", "' OR '1'='1")]
    [InlineData("admin' --", "x")]
    [InlineData("admin'; DROP TABLE Usuarios; --", "x")]
    [InlineData("' UNION SELECT Id, Username, PasswordHash, Rol FROM Usuarios --", "x")]
    public async Task Login_ConInyeccionSql_NoAutentica_YNoAlteraLaBaseDeDatos(string usuario, string password)
    {
        var resultado = await CrearServicio().LoginAsync(usuario, password, default);

        Assert.Null(resultado.Sesion);
        await using var db = _testDb.CrearContexto();
        Assert.Equal(3, db.Usuarios.Count()); // la tabla sigue intacta
    }

    [Fact]
    public async Task Login_TrasVariosFallos_BloqueaLaCuentaAunqueLaContrasenaSeaCorrecta()
    {
        var servicio = CrearServicio();
        for (var i = 0; i < LoginThrottle.FallosPermitidos; i++)
            await servicio.LoginAsync("vendedor", "incorrecta", default);

        var resultado = await servicio.LoginAsync("vendedor", TestDb.PasswordDePrueba, default);

        Assert.Null(resultado.Sesion);
        Assert.NotNull(resultado.BloqueadoPor);
        Assert.True(resultado.BloqueadoPor <= LoginThrottle.DuracionBloqueo);
    }

    [Fact]
    public async Task Login_ExitosoAntesDelLimite_ReiniciaElContadorDeFallos()
    {
        var servicio = CrearServicio();
        for (var i = 0; i < LoginThrottle.FallosPermitidos - 1; i++)
            await servicio.LoginAsync("vendedor", "incorrecta", default);
        Assert.NotNull((await servicio.LoginAsync("vendedor", TestDb.PasswordDePrueba, default)).Sesion);

        // Un nuevo fallo no bloquea: el contador volvió a cero con el login exitoso.
        await servicio.LoginAsync("vendedor", "incorrecta", default);
        Assert.NotNull((await servicio.LoginAsync("vendedor", TestDb.PasswordDePrueba, default)).Sesion);
    }

    [Fact]
    public void JwtOptions_ConClaveCorta_FallaAlValidar()
    {
        Assert.Throws<InvalidOperationException>(() => new JwtOptions { Key = "clave-secreta" }.Validar());
    }
}
