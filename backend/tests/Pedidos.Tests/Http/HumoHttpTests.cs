using System.Net;
using Pedidos.Api.Domain;

namespace Pedidos.Tests.Http;

/// <summary>La API arranca en modo producción y cada rol puede iniciar sesión con Google Authenticator.</summary>
[Collection(ApiColeccion.Nombre)]
public class HumoHttpTests(ApiEnVivo api)
{
    [ApiFact]
    public async Task Health_Responde_SinAutenticacion()
    {
        using var http = api.Cliente();
        Assert.Equal(HttpStatusCode.OK, (await http.GetAsync("health")).StatusCode);
    }

    [ApiTheory]
    [InlineData(Roles.Vendedor)]
    [InlineData(Roles.Admin)]
    [InlineData(Roles.Bodega)]
    [InlineData(Roles.Compras)]
    [InlineData(Roles.Contador)]
    public async Task CadaRol_EntraConGoogleAuthenticator(string rol)
    {
        using var http = await api.ComoAsync(rol);
        Assert.Equal(HttpStatusCode.OK, (await http.GetAsync("api/cuenta/seguridad")).StatusCode);
    }
}
