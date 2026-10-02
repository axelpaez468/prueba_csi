using System.Net;
using Pedidos.Api.Domain;
using Pedidos.Tests.Infra;

namespace Pedidos.Tests.Http;

/// <summary>Defensas contra abuso: límites de peticiones por IP y por usuario, y bloqueo por fuerza bruta.</summary>
[Collection(ApiColeccion.Nombre)]
public class LimitesHttpTests(ApiEnVivo api)
{
    [ApiFact]
    public async Task Login_MasDeDiezIntentosPorMinutoDesdeLaMismaIp_Da429ConRetryAfter()
    {
        using var http = api.Cliente(); // una sola IP
        var codigos = new List<HttpStatusCode>();
        for (var i = 0; i < 12; i++)
            codigos.Add((await http.PostJson("api/auth/login", new { email = $"nadie{i}@pedidos.test", password = "Intento-de-fuerza-1" })).StatusCode);

        Assert.All(codigos.Take(10), c => Assert.Equal(HttpStatusCode.Unauthorized, c));
        Assert.Equal(HttpStatusCode.TooManyRequests, codigos[^1]);
        using var r = await http.PostJson("api/auth/login", new { email = "otro@pedidos.test", password = "Intento-de-fuerza-1" });
        Assert.True(r.Headers.RetryAfter is not null);

        using var otraIp = api.Cliente(); // el límite es por IP: otra computadora puede entrar
        Assert.Equal(HttpStatusCode.Unauthorized,
            (await otraIp.PostJson("api/auth/login", new { email = "nadie@pedidos.test", password = "Intento-de-fuerza-1" })).StatusCode);
    }

    [ApiFact]
    public async Task CincoContrasenasIncorrectas_BloqueanLaCuenta_AunqueLuegoUseLaCorrecta()
    {
        var (_, email) = await api.CrearUsuarioAsync(Roles.Vendedor);
        for (var i = 0; i < 5; i++)
        {
            using var http = api.Cliente(); // IPs distintas: el bloqueo es de la cuenta, no de la IP
            await http.PostJson("api/auth/login", new { email, password = $"Incorrecta-{i}-xyz" }).Esperar(HttpStatusCode.Unauthorized);
        }

        using var otra = api.Cliente();
        using var r = await otra.PostJson("api/auth/login", new { email, password = TestDb.PasswordDePrueba });
        Assert.Equal(HttpStatusCode.TooManyRequests, r.StatusCode);
        Assert.Contains("intentos", await r.Content.ReadAsStringAsync());
    }

    [ApiFact]
    public async Task Recuperar_MasDeCincoVecesDesdeLaMismaIp_Da429()
    {
        using var http = api.Cliente();
        var codigos = new List<HttpStatusCode>();
        for (var i = 0; i < 6; i++)
            codigos.Add((await http.PostJson("api/auth/recuperar", new { email = $"x{i}@pedidos.test" })).StatusCode);

        Assert.All(codigos.Take(5), c => Assert.Equal(HttpStatusCode.Accepted, c));
        Assert.Equal(HttpStatusCode.TooManyRequests, codigos[^1]);
    }

    [ApiFact]
    public async Task Ventas_MasDeVeintePorMinutoDelMismoUsuario_Da429()
    {
        using var vendedor = await api.ComoNuevoAsync(Roles.Vendedor);
        var codigos = new List<HttpStatusCode>();
        for (var i = 0; i < 22; i++)
            codigos.Add((await vendedor.PostJson("api/pedidos", new { lineas = Array.Empty<object>() })).StatusCode); // inválidas: no gastan stock

        Assert.All(codigos.Take(20), c => Assert.Equal(HttpStatusCode.BadRequest, c));
        Assert.Equal(HttpStatusCode.TooManyRequests, codigos[^1]);
    }

    [ApiFact]
    public async Task MasDeTrescientasPeticionesPorMinutoDesdeUnaIp_Da429_YLaApiSigueAtendiendoAOtros()
    {
        using var http = api.Cliente();
        var r = await HttpExt.Simultaneas(320, _ => http.GetAsync("health"));

        Assert.True(r.Count(x => x.Status == HttpStatusCode.TooManyRequests) >= 15, $"429: {r.Count(x => x.Status == HttpStatusCode.TooManyRequests)}");
        Assert.DoesNotContain(r, x => (int)x.Status >= 500);
        using var otra = api.Cliente();
        Assert.Equal(HttpStatusCode.OK, (await otra.GetAsync("health")).StatusCode);
    }
}
