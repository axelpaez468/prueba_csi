using System.Net;
using System.Text;
using Pedidos.Api.Domain;

namespace Pedidos.Tests.Http;

/// <summary>
/// Datos mal formados, maliciosos o fuera de rango: la API debe responder un error claro (4xx) y nunca un 500,
/// ni filtrar detalles internos (stack trace, SQL, nombres de clases).
/// </summary>
[Collection(ApiColeccion.Nombre)]
public class EntradasHttpTests(ApiEnVivo api)
{
    private static void SinDetallesInternos(string cuerpo)
    {
        foreach (var fuga in new[] { "   at ", "Exception", "Pedidos.Api.", "Microsoft.", "SqlClient", "SELECT ", "stack" })
            Assert.DoesNotContain(fuga, cuerpo, StringComparison.OrdinalIgnoreCase);
    }

    public static IEnumerable<object[]> CuerposRotos() => new[]
    {
        new object[] { "{" },
        new object[] { "no es json" },
        new object[] { "{\"lineas\": \"texto\"}" },
        new object[] { "{\"lineas\": [{\"productoId\": \"uno\", \"cantidad\": 1}]}" },
        new object[] { "{\"lineas\": [{\"productoId\": 1, \"cantidad\": 99999999999999999999}]}" },
        new object[] { "{\"lineas\": [{\"productoId\": 1, \"cantidad\": 1.5}]}" },
        new object[] { "{\"lineas\": null}" },
        new object[] { "[]" },
        new object[] { "null" },
        new object[] { "{\"lineas\": [null]}" },
    };

    [ApiTheory]
    [MemberData(nameof(CuerposRotos))]
    public async Task CuerpoMalFormado_Da400_SinDetallesInternos(string cuerpo)
    {
        using var http = await api.ComoNuevoAsync(Roles.Vendedor);
        using var r = await http.PostTexto("api/pedidos", cuerpo);
        var texto = await r.Content.ReadAsStringAsync();

        Assert.True(r.StatusCode == HttpStatusCode.BadRequest, $"{(int)r.StatusCode} {texto}");
        Assert.Contains("\"error\"", texto);
        SinDetallesInternos(texto);
    }

    /// <summary>Listas con elementos null o vacíos en cada endpoint que recibe listas (antes daban error 500).</summary>
    [ApiTheory]
    [InlineData(Roles.Vendedor, "POST", "api/pedidos", "{\"lineas\":[null]}")]
    [InlineData(Roles.Vendedor, "POST", "api/pedidos", "{\"lineas\":[{\"productoId\":1,\"cantidad\":1},null]}")]
    [InlineData(Roles.Compras, "POST", "api/compras/ordenes", "{\"proveedorId\":1,\"lineas\":[null]}")]
    [InlineData(Roles.Contador, "POST", "api/contabilidad/partidas", "{\"concepto\":\"Prueba de nulos\",\"lineas\":[null,null]}")]
    [InlineData(Roles.Admin, "PUT", "api/reportes/pronostico/probabilidades", "{\"etapas\":[null,null,null,null,null,null]}")]
    [InlineData(Roles.Admin, "PUT", "api/reportes/pronostico/probabilidades", "{\"etapas\":null}")]
    [InlineData(Roles.Admin, "PUT", "api/reportes/pronostico/probabilidades", "{}")]
    [InlineData(Roles.Bodega, "PUT", "api/inventario/productos/1", "{\"nombre\":\"Teclado\",\"precio\":150,\"stockMinimo\":0,\"especificaciones\":[null]}")]
    public async Task ListasConNulos_NuncaDan500(string rol, string metodo, string url, string cuerpo)
    {
        using var http = await api.ComoNuevoAsync(rol);
        using var r = await http.SendAsync(new HttpRequestMessage(new HttpMethod(metodo), url)
        {
            Content = new StringContent(cuerpo, Encoding.UTF8, "application/json")
        });
        var texto = await r.Content.ReadAsStringAsync();
        Assert.True((int)r.StatusCode < 500, $"{metodo} {url} {cuerpo}: {(int)r.StatusCode} {texto}");
        SinDetallesInternos(texto);
    }

    [ApiFact]
    public async Task CuerpoGigante_Da413()
    {
        using var http = await api.ComoAsync(Roles.Vendedor);
        var enorme = "{\"nombre\":\"" + new string('a', 200_000) + "\"}";
        using var r = await http.PostTexto("api/clientes", enorme);
        Assert.Equal(HttpStatusCode.RequestEntityTooLarge, r.StatusCode);
        SinDetallesInternos(await r.Content.ReadAsStringAsync());
    }

    [ApiFact]
    public async Task UrlDemasiadoLarga_SeRechaza_SinCaerse()
    {
        using var http = await api.ComoAsync(Roles.Vendedor);
        using var r = await http.GetAsync("api/clientes?buscar=" + new string('x', 6000));
        Assert.True((int)r.StatusCode is 414 or 400 or 431, $"{(int)r.StatusCode}");
        Assert.Equal(HttpStatusCode.OK, (await http.GetAsync("api/clientes")).StatusCode); // la API sigue en pie
    }

    [ApiFact]
    public async Task TipoDeContenidoIncorrecto_Da415()
    {
        using var http = await api.ComoAsync(Roles.Vendedor);
        using var r = await http.PostTexto("api/clientes", "nit=CF", "application/x-www-form-urlencoded");
        Assert.Equal(HttpStatusCode.UnsupportedMediaType, r.StatusCode);
    }

    [ApiTheory]
    [InlineData("api/pedidos/0")]
    [InlineData("api/pedidos/-1")]
    [InlineData("api/pedidos/99999999999")]   // no cabe en int: la ruta no coincide
    [InlineData("api/pedidos/abc")]
    [InlineData("api/pedidos/1%27%20OR%201=1")]
    [InlineData("api/no-existe")]
    public async Task IdsYRutasInvalidas_Dan404(string url)
    {
        using var http = await api.ComoAsync(Roles.Vendedor);
        using var r = await http.GetAsync(url);
        Assert.Equal(HttpStatusCode.NotFound, r.StatusCode);
    }

    [ApiFact]
    public async Task MetodoNoPermitido_Da405()
    {
        using var http = await api.ComoAsync(Roles.Admin);
        using var r = await http.DeleteAsync("api/pedidos");
        Assert.Equal(HttpStatusCode.MethodNotAllowed, r.StatusCode);
    }

    [ApiTheory]
    [InlineData("' OR '1'='1")]
    [InlineData("'; DROP TABLE Clientes; --")]
    [InlineData("%")]
    [InlineData("_")]
    [InlineData("[a-z]")]
    [InlineData("\\")]
    public async Task BusquedasConCaracteresEspeciales_NoInyectanNiComodines(string texto)
    {
        using var http = await api.ComoAsync(Roles.Vendedor);
        var lista = await http.GetAsync("api/clientes?buscar=" + Uri.EscapeDataString(texto)).Ok();
        Assert.Equal(0, lista.GetArrayLength()); // ningún cliente se llama así; "%" o "_" no deben devolver todos

        await using var db = api.Db();
        Assert.True(db.Clientes.Any()); // la tabla sigue ahí
    }

    [ApiFact]
    public async Task TextoConHtmlOScript_SeGuardaYDevuelveTalCual_ComoJson()
    {
        using var http = await api.ComoAsync(Roles.Vendedor);
        const string nombre = "<script>alert('x')</script> Ñandú & Cía 😀";
        var c = await http.PostJson("api/clientes", new { nit = NitValido(), nombre }).Creado();

        Assert.Equal(nombre, c.Str("nombre"));
        using var r = await http.GetAsync("api/clientes?buscar=" + Uri.EscapeDataString("Ñandú"));
        Assert.Equal("application/json", r.Content.Headers.ContentType?.MediaType);
        Assert.Contains(nombre, (await r.Json()).EnumerateArray().Select(x => x.Str("nombre")));
    }

    [ApiTheory]
    [InlineData("\u0000nombre")]
    [InlineData("   ")]
    public async Task NombresVaciosOConCaracteresDeControl_SeRechazan_OSeLimpian(string nombre)
    {
        using var http = await api.ComoAsync(Roles.Vendedor);
        using var r = await http.PostJson("api/clientes", new { nit = NitValido(), nombre });
        var texto = await r.Content.ReadAsStringAsync();
        Assert.True(r.StatusCode is HttpStatusCode.BadRequest or HttpStatusCode.Created, $"{(int)r.StatusCode} {texto}");
        if (r.StatusCode == HttpStatusCode.Created) Assert.DoesNotContain("\\u0000", texto);
    }

    [ApiTheory]
    [InlineData(0)]
    [InlineData(-5)]
    [InlineData(1001)]        // más de lo permitido por línea
    [InlineData(int.MaxValue)]
    public async Task CantidadesFueraDeRango_SeRechazan(int cantidad)
    {
        using var http = await api.ComoNuevoAsync(Roles.Vendedor);
        await http.PostJson("api/pedidos", new { lineas = new[] { new { productoId = 1, cantidad } } }).Esperar(HttpStatusCode.BadRequest);
    }

    [ApiFact]
    public async Task PrecioEnviadoPorElCliente_SeIgnora()
    {
        using var http = await api.ComoNuevoAsync(Roles.Vendedor);
        var p = await http.PostTexto("api/pedidos",
            "{\"lineas\":[{\"productoId\":1,\"cantidad\":1,\"precioUnitario\":0.01,\"subtotal\":0.01}],\"total\":0.01}").Creado();
        Assert.Equal(150.00m, p.Dec("total")); // precio de la base de datos
    }

    [ApiTheory]
    [InlineData(1e30)]
    [InlineData(-1)]
    [InlineData(0)]
    public async Task PrecioDeProductoFueraDeRango_SeRechaza(double precio)
    {
        using var http = await api.ComoAsync(Roles.Bodega);
        var valor = precio.ToString(System.Globalization.CultureInfo.InvariantCulture);
        using var r = await http.PostTexto("api/inventario/productos",
            $"{{\"codigo\":\"X{Random.Shared.Next(100000, 999999)}\",\"nombre\":\"Prueba\",\"precio\":{valor},\"stockMinimo\":0}}");
        var texto = await r.Content.ReadAsStringAsync();
        Assert.True(r.StatusCode == HttpStatusCode.BadRequest, $"{(int)r.StatusCode} {texto}");
        SinDetallesInternos(texto);
    }

    [ApiTheory]
    [InlineData("2026-13-45", "2026-01-01")]
    [InlineData("ayer", "hoy")]
    [InlineData("2026-09-30", "2026-09-01")]   // al revés
    [InlineData("0001-01-01", "9999-12-31")]   // rango absurdo
    public async Task RangosDeFechasInvalidos_EnReportes_NoTumbanLaApi(string desde, string hasta)
    {
        using var http = await api.ComoAsync(Roles.Contador);
        foreach (var url in new[] { "api/reportes/ventas", "api/reportes/pronostico", "api/contabilidad/partidas" })
        {
            using var r = await http.GetAsync($"{url}?desde={desde}&hasta={hasta}");
            var texto = await r.Content.ReadAsStringAsync();
            Assert.True((int)r.StatusCode < 500, $"{url} {desde}..{hasta}: {(int)r.StatusCode} {texto}");
            SinDetallesInternos(texto);
        }
    }

    [ApiFact]
    public async Task Respuestas_LlevanCabecerasDeSeguridad_YNoAnuncianElServidor()
    {
        using var http = await api.ComoAsync(Roles.Vendedor);
        using var r = await http.GetAsync("api/productos");

        Assert.Equal("nosniff", r.Headers.GetValues("X-Content-Type-Options").Single());
        Assert.Equal("DENY", r.Headers.GetValues("X-Frame-Options").Single());
        Assert.Contains("default-src 'none'", r.Headers.GetValues("Content-Security-Policy").Single());
        Assert.Contains("no-store", r.Headers.CacheControl!.ToString());
        Assert.False(r.Headers.Contains("Server"));
        Assert.False(r.Headers.Contains("X-Powered-By"));
    }

    [ApiFact]
    public async Task Swagger_NoSePublicaEnProduccion()
    {
        using var http = api.Cliente();
        foreach (var url in new[] { "swagger/index.html", "swagger/v1/swagger.json" })
        {
            using var r = await http.GetAsync(url);
            Assert.True(r.StatusCode is HttpStatusCode.NotFound or HttpStatusCode.Unauthorized, $"{url}: {(int)r.StatusCode}");
        }
    }

    [ApiTheory]
    [InlineData("http://localhost:8080", true)]
    [InlineData("https://sitio-malicioso.example", false)]
    [InlineData("null", false)]
    public async Task Cors_SoloPermiteElFrontend(string origen, bool permitido)
    {
        using var http = api.Cliente();
        using var req = new HttpRequestMessage(HttpMethod.Options, "api/pedidos");
        req.Headers.Add("Origin", origen);
        req.Headers.Add("Access-Control-Request-Method", "POST");
        req.Headers.Add("Access-Control-Request-Headers", "authorization,content-type");
        using var r = await http.SendAsync(req);

        var acao = r.Headers.TryGetValues("Access-Control-Allow-Origin", out var v) ? v.Single() : null;
        if (permitido) Assert.Equal(origen, acao);
        else Assert.Null(acao);
        Assert.NotEqual("*", acao);
    }

    [ApiFact]
    public async Task ImagenPublica_DeProductoOImagenInexistente_Da404_SinRevelarNada()
    {
        using var http = api.Cliente();
        foreach (var url in new[] { "api/productos/1/imagenes/999999", "api/productos/999999/imagenes/1", "api/productos/1/imagenes/-1" })
        {
            using var r = await http.GetAsync(url);
            Assert.Equal(HttpStatusCode.NotFound, r.StatusCode);
        }
    }

    [ApiFact]
    public async Task SubirUnArchivoQueNoEsImagen_SeRechaza_AunqueDigaPng()
    {
        using var http = await api.ComoAsync(Roles.Bodega);
        var html = new ByteArrayContent(Encoding.UTF8.GetBytes("<html><script>alert(1)</script></html>"));
        html.Headers.ContentType = new("image/png");
        using var r = await http.PostAsync("api/inventario/productos/1/imagenes", new MultipartFormDataContent { { html, "archivo", "foto.png" } });
        Assert.Equal(HttpStatusCode.BadRequest, r.StatusCode);
    }

    [ApiFact]
    public async Task SubirUnaImagenMayorAlLimite_Da413()
    {
        using var http = await api.ComoAsync(Roles.Bodega);
        var bytes = new byte[3 * 1024 * 1024];
        new byte[] { 0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A }.CopyTo(bytes, 0); // firma PNG
        var contenido = new ByteArrayContent(bytes);
        contenido.Headers.ContentType = new("image/png");
        try
        {
            using var r = await http.PostAsync("api/inventario/productos/1/imagenes",
                new MultipartFormDataContent { { contenido, "archivo", "grande.png" } });
            Assert.True(r.StatusCode is HttpStatusCode.RequestEntityTooLarge or HttpStatusCode.BadRequest, $"{(int)r.StatusCode}");
        }
        catch (HttpRequestException)
        {
            // También vale: Kestrel corta la conexión en cuanto el cuerpo pasa el límite, sin leer los 3 MB.
        }

        await using var db = api.Db();
        Assert.DoesNotContain(db.ProductoImagenes, i => i.Datos.Length > 2 * 1024 * 1024);
        using var otra = await api.ComoAsync(Roles.Bodega);
        Assert.Equal(HttpStatusCode.OK, (await otra.GetAsync("api/inventario/productos")).StatusCode); // la API sigue en pie
    }

    private static int _nit = 1_000_000;

    /// <summary>NIT guatemalteco válido y distinto en cada llamada (módulo 11).</summary>
    public static string NitValido()
    {
        while (true)
        {
            var n = Interlocked.Increment(ref _nit).ToString();
            var suma = n.Reverse().Select((c, i) => (c - '0') * (i + 2)).Sum();
            var dv = (11 - suma % 11) % 11;
            if (dv == 10) continue; // evita la "K" para simplificar
            return n + dv;
        }
    }
}
