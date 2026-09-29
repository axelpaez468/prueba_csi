using System.IdentityModel.Tokens.Jwt;
using Microsoft.Extensions.Options;
using Pedidos.Api.Security;
using Pedidos.Api.Services;
using Pedidos.Tests.Infra;

namespace Pedidos.Tests;

public class AuthServiceTests : IDisposable
{
    private readonly TestDb _testDb = new();

    public void Dispose() => _testDb.Dispose();

    private AuthService CrearServicio()
    {
        var options = Options.Create(new JwtOptions { Key = new string('k', JwtOptions.MinKeyBytes) });
        return new AuthService(_testDb.CrearContexto(), new TokenService(options, TimeProvider.System));
    }

    [Fact]
    public async Task Login_ConCredencialesValidas_DevuelveTokenConRolYExpiracion()
    {
        var resultado = await CrearServicio().LoginAsync("admin", TestDb.PasswordDePrueba, default);

        Assert.NotNull(resultado);
        var token = new JwtSecurityTokenHandler().ReadJwtToken(resultado.Token);
        Assert.Equal("ADMIN", token.Claims.Single(c => c.Type == JwtClaims.Role).Value);
        Assert.Equal(TestDb.AdminId.ToString(), token.Claims.Single(c => c.Type == JwtClaims.UserId).Value);
        Assert.True(token.ValidTo > DateTime.UtcNow);
    }

    [Theory]
    [InlineData("admin", "clave-incorrecta")]
    [InlineData("no-existe", TestDb.PasswordDePrueba)]
    public async Task Login_ConCredencialesInvalidas_DevuelveNull(string usuario, string password)
    {
        Assert.Null(await CrearServicio().LoginAsync(usuario, password, default));
    }

    [Fact]
    public void JwtOptions_ConClaveCorta_FallaAlValidar()
    {
        Assert.Throws<InvalidOperationException>(() => new JwtOptions { Key = "clave-secreta" }.Validar());
    }
}
