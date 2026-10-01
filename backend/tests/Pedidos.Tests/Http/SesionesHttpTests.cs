using System.IdentityModel.Tokens.Jwt;
using System.Net;
using System.Net.Http.Headers;
using System.Security.Claims;
using System.Text;
using Microsoft.IdentityModel.Tokens;
using Pedidos.Api.Domain;
using Pedidos.Tests.Infra;

namespace Pedidos.Tests.Http;

/// <summary>Tokens falsificados, vencidos o alterados, y sesiones que deben cerrarse.</summary>
[Collection(ApiColeccion.Nombre)]
public class SesionesHttpTests(ApiEnVivo api)
{
    private const string Protegido = "api/cuenta/seguridad";

    private async Task<HttpStatusCode> ConToken(string token)
    {
        using var http = api.Cliente();
        using var req = new HttpRequestMessage(HttpMethod.Get, Protegido);
        req.Headers.TryAddWithoutValidation("Authorization", "Bearer " + token);
        return (await http.SendAsync(req)).StatusCode;
    }

    /// <summary>Administrador nuevo (versión de sesión 0) para fabricarle tokens.</summary>
    private async Task<int> Admin() => (await api.CrearUsuarioAsync(Roles.Admin)).Id;

    /// <summary>Token como los de la API, con lo que se quiera cambiar.</summary>
    private string Fabricar(int usuario, string? clave = null, string issuer = "Pedidos.Api", string audiencia = "Pedidos.Frontend",
        DateTime? expira = null, string rol = Roles.Admin, int? version = 0)
    {
        var claims = new List<Claim>
        {
            new("sub", usuario.ToString()), new("unique_name", "x"), new("email", "x@x.test"), new("role", rol),
            new(JwtRegisteredClaimNames.Jti, Guid.NewGuid().ToString())
        };
        if (version is not null) claims.Add(new Claim("sv", version.ToString()!));
        var key = new SymmetricSecurityKey(Encoding.UTF8.GetBytes(clave ?? api.JwtKey));
        var fin = expira ?? DateTime.UtcNow.AddMinutes(30);
        return new JwtSecurityTokenHandler().WriteToken(new JwtSecurityToken(issuer, audiencia, claims,
            notBefore: fin.AddHours(-2), expires: fin, signingCredentials: new SigningCredentials(key, SecurityAlgorithms.HmacSha256)));
    }

    [ApiFact]
    public async Task TokenFabricadoConLaClaveCorrecta_Funciona()
    {
        // Control: confirma que los tokens "fabricados" de esta clase solo fallan por lo que cada prueba cambia.
        Assert.Equal(HttpStatusCode.OK, await ConToken(Fabricar(await Admin())));
    }

    [ApiTheory]
    [InlineData("")]
    [InlineData("basura")]
    [InlineData("eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxIn0.firma")]
    public async Task TokenMalFormado_Responde401(string token) =>
        Assert.Equal(HttpStatusCode.Unauthorized, await ConToken(token));

    [ApiFact]
    public async Task TokenFirmadoConOtraClave_Responde401() =>
        Assert.Equal(HttpStatusCode.Unauthorized, await ConToken(Fabricar(await Admin(), clave: Convert.ToBase64String(new byte[48]))));

    [ApiFact]
    public async Task TokenSinFirma_AlgNone_Responde401()
    {
        static string B64(string s) => Base64UrlEncoder.Encode(s);
        var token = $"{B64("{\"alg\":\"none\",\"typ\":\"JWT\"}")}.{B64($"{{\"sub\":\"{TestDb.AdminId}\",\"role\":\"ADMIN\",\"sv\":\"0\",\"iss\":\"Pedidos.Api\",\"aud\":\"Pedidos.Frontend\",\"exp\":{DateTimeOffset.UtcNow.AddHours(1).ToUnixTimeSeconds()}}}")}.";
        Assert.Equal(HttpStatusCode.Unauthorized, await ConToken(token));
    }

    [ApiFact]
    public async Task TokenRealConElRolCambiado_Responde401()
    {
        // Un vendedor edita su propio token para decir que es administrador (sin poder volver a firmarlo).
        var real = await api.TokenAsync(Roles.Vendedor);
        var partes = real.Split('.');
        var cuerpo = Base64UrlEncoder.Decode(partes[1]).Replace("\"VENDEDOR\"", "\"ADMIN\"");
        var alterado = $"{partes[0]}.{Base64UrlEncoder.Encode(cuerpo)}.{partes[2]}";

        Assert.Equal(HttpStatusCode.Unauthorized, await ConToken(alterado));
        using var http = api.Cliente(alterado);
        Assert.Equal(HttpStatusCode.Unauthorized, (await http.GetAsync("api/admin/usuarios")).StatusCode);
    }

    [ApiFact]
    public async Task TokenVencido_Responde401() =>
        Assert.Equal(HttpStatusCode.Unauthorized, await ConToken(Fabricar(await Admin(), expira: DateTime.UtcNow.AddMinutes(-5))));

    [ApiTheory]
    [InlineData("OtroEmisor", "Pedidos.Frontend")]
    [InlineData("Pedidos.Api", "OtraAudiencia")]
    public async Task TokenDeOtroEmisorOAudiencia_Responde401(string issuer, string audiencia) =>
        Assert.Equal(HttpStatusCode.Unauthorized, await ConToken(Fabricar(await Admin(), issuer: issuer, audiencia: audiencia)));

    [ApiFact]
    public async Task TokenSinVersionDeSesion_Responde401() =>
        Assert.Equal(HttpStatusCode.Unauthorized, await ConToken(Fabricar(await Admin(), version: null)));

    [ApiFact]
    public async Task TokenDeUnUsuarioQueNoExiste_Responde401() =>
        Assert.Equal(HttpStatusCode.Unauthorized, await ConToken(Fabricar(987_654)));

    [ApiFact]
    public async Task ElDesafioDelLogin_NoSirveComoSesion()
    {
        // El token del paso 1 (antes del código de Google Authenticator) no debe dar acceso a la API.
        var (_, email) = await api.CrearUsuarioAsync(Roles.Admin);
        using var http = api.Cliente();
        var desafio = (await http.PostJson("api/auth/login", new { email, password = TestDb.PasswordDePrueba }).Ok()).Str("desafio");

        Assert.Equal(HttpStatusCode.Unauthorized, await ConToken(desafio));
    }

    [ApiFact]
    public async Task ElDesafio_SoloSirveUnaVez()
    {
        var (_, email) = await api.CrearUsuarioAsync(Roles.Contador);
        await api.EntrarAsync(email, TestDb.PasswordDePrueba); // configura Google Authenticator

        using var http = api.Cliente();
        var desafio = (await http.PostJson("api/auth/login", new { email, password = TestDb.PasswordDePrueba }).Ok()).Str("desafio");
        await http.PostJson("api/auth/login/verificar", new { desafio, codigo = api.CodigoTotp(email) }).Ok();

        await Rechazado(http.PostJson("api/auth/login/verificar", new { desafio, codigo = api.CodigoTotp(email) }));
    }

    /// <summary>La API puede responder 401 (código incorrecto) o 400 ("inicia sesión de nuevo"): lo que importa es que no entra.</summary>
    private static async Task Rechazado(Task<HttpResponseMessage> peticion)
    {
        using var r = await peticion;
        var cuerpo = await r.Content.ReadAsStringAsync();
        Assert.True(r.StatusCode is HttpStatusCode.Unauthorized or HttpStatusCode.BadRequest, $"{(int)r.StatusCode} {cuerpo}");
        Assert.DoesNotContain("token", cuerpo);
    }

    [ApiFact]
    public async Task CodigoIncorrecto_NoEntra_YTrasCincoIntentosElDesafioSeInvalida()
    {
        var (_, email) = await api.CrearUsuarioAsync(Roles.Bodega);
        await api.EntrarAsync(email, TestDb.PasswordDePrueba);

        using var http = api.Cliente();
        var desafio = (await http.PostJson("api/auth/login", new { email, password = TestDb.PasswordDePrueba }).Ok()).Str("desafio");
        for (var i = 0; i < 5; i++)
            await Rechazado(http.PostJson("api/auth/login/verificar", new { desafio, codigo = "000000" }));

        // Ni con el código correcto: hay que volver a poner la contraseña.
        await Rechazado(http.PostJson("api/auth/login/verificar", new { desafio, codigo = api.CodigoTotp(email) }));
    }

    [ApiFact]
    public async Task CambiarLaContrasena_CierraLasSesionesAnteriores()
    {
        var (_, email) = await api.CrearUsuarioAsync(Roles.Vendedor);
        var viejo = await api.EntrarAsync(email, TestDb.PasswordDePrueba);
        using var http = api.Cliente(viejo);

        var nueva = "Otra-clave-segura-2026";
        var nuevoToken = (await http.PostJson("api/cuenta/password", new { actual = TestDb.PasswordDePrueba, nueva }).Ok()).Str("token");

        Assert.Equal(HttpStatusCode.Unauthorized, await ConToken(viejo));
        Assert.Equal(HttpStatusCode.OK, await ConToken(nuevoToken)); // la sesión desde donde se cambió sigue
        await api.EntrarAsync(email, nueva);
        await Assert.ThrowsAsync<InvalidOperationException>(() => api.EntrarAsync(email, TestDb.PasswordDePrueba));
    }

    [ApiFact]
    public async Task CambiarLaContrasena_ConLaActualIncorrecta_OFiltrada_SeRechaza()
    {
        var (_, email) = await api.CrearUsuarioAsync(Roles.Vendedor);
        using var http = api.Cliente(await api.EntrarAsync(email, TestDb.PasswordDePrueba));

        var r1 = await http.PostJson("api/cuenta/password", new { actual = "no-es-la-actual-123", nueva = "Otra-clave-segura-2026" });
        Assert.True(r1.StatusCode is HttpStatusCode.BadRequest or HttpStatusCode.Unauthorized, $"{(int)r1.StatusCode}");
        await http.PostJson("api/cuenta/password", new { actual = TestDb.PasswordDePrueba, nueva = ApiEnVivo.PasswordFiltrada })
            .Rechazo("filtr");
        await http.PostJson("api/cuenta/password", new { actual = TestDb.PasswordDePrueba, nueva = "corta" }).Esperar(HttpStatusCode.BadRequest);
    }

    [ApiFact]
    public async Task DesactivarAlUsuario_LeQuitaElAccesoDeInmediato()
    {
        var (id, email) = await api.CrearUsuarioAsync(Roles.Compras);
        var token = await api.EntrarAsync(email, TestDb.PasswordDePrueba);
        using var admin = await api.ComoAsync(Roles.Admin);

        await admin.PostJson($"api/admin/usuarios/{id}/desactivar").Ok();

        Assert.Equal(HttpStatusCode.Unauthorized, await ConToken(token));
        using var http = api.Cliente();
        await http.PostJson("api/auth/login", new { email, password = TestDb.PasswordDePrueba }).Esperar(HttpStatusCode.Forbidden);

        await admin.PostJson($"api/admin/usuarios/{id}/activar").Ok();
        await api.EntrarAsync(email, TestDb.PasswordDePrueba);
    }

    [ApiFact]
    public async Task CambiarElRol_CierraLaSesion_YElNuevoTokenTraeElRolNuevo()
    {
        var (id, email) = await api.CrearUsuarioAsync(Roles.Vendedor);
        var token = await api.EntrarAsync(email, TestDb.PasswordDePrueba);
        using var admin = await api.ComoAsync(Roles.Admin);
        var u = await admin.GetAsync($"api/admin/usuarios/{id}").Ok();

        await admin.PutJson($"api/admin/usuarios/{id}", new
        {
            nombre = u.Str("nombre"), apellido = u.Str("apellido"), telefono = "55550199", email, codigoCorporativo = u.Str("codigoCorporativo"),
            rol = Roles.Bodega
        }).Ok();

        Assert.Equal(HttpStatusCode.Unauthorized, await ConToken(token));
        using var bodega = api.Cliente(await api.EntrarAsync(email, TestDb.PasswordDePrueba));
        Assert.Equal(HttpStatusCode.OK, (await bodega.GetAsync("api/inventario/productos")).StatusCode);
        Assert.Equal(HttpStatusCode.Forbidden, (await bodega.GetAsync("api/clientes")).StatusCode);
    }

    [ApiFact]
    public async Task LoginConCorreoInexistente_OContrasenaIncorrecta_DaElMismoMensaje()
    {
        // No se revela qué correos existen.
        using var http = api.Cliente();
        var a = await http.PostJson("api/auth/login", new { email = "nadie@pedidos.test", password = "Cualquier-cosa-1" })
            .Esperar(HttpStatusCode.Unauthorized);
        var (_, email) = await api.CrearUsuarioAsync(Roles.Vendedor);
        var b = await http.PostJson("api/auth/login", new { email, password = "Cualquier-cosa-1" }).Esperar(HttpStatusCode.Unauthorized);
        Assert.Equal(a.Str("error"), b.Str("error"));
    }

    [ApiFact]
    public async Task CabeceraAuthorization_ConOtroEsquema_Responde401()
    {
        using var http = api.Cliente();
        http.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Basic", Convert.ToBase64String("admin:admin"u8.ToArray()));
        Assert.Equal(HttpStatusCode.Unauthorized, (await http.GetAsync(Protegido)).StatusCode);
    }
}
