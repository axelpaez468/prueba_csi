using Pedidos.Api.Notificaciones;
using Pedidos.Api.Services.Seguridad;
using Pedidos.Tests.Infra;

namespace Pedidos.Tests;

public class CorreosTests : IDisposable
{
    private readonly TestDb _testDb = new();
    private readonly ServiciosSeguridad _s = new();

    public void Dispose() => _testDb.Dispose();

    private static PlantillaCorreo Ejemplo(string nombre = "Ana") => new(
        "Asunto de prueba", "Título", $"Hola {nombre}:", new[] { "Primer párrafo." },
        TipoCorreo.Seguridad, new[] { ("Dispositivo", "Chrome en Windows") },
        "Crear mi contraseña", "http://localhost:8080/?restablecer=abc", "Vence en 30 minutos.", "Si no fuiste tú, avisa.");

    [Fact]
    public void Html_IncluyeElBoton_LosDatos_YElAviso()
    {
        var html = Ejemplo().Html();

        Assert.StartsWith("<!DOCTYPE html>", html.TrimStart());
        Assert.Contains("href=\"http://localhost:8080/?restablecer=abc\"", html);
        Assert.Contains("Crear mi contraseña", html);
        Assert.Contains("Chrome en Windows", html);
        Assert.Contains("Si no fuiste tú, avisa.", html);
        Assert.Contains("AVISO DE SEGURIDAD", html);
    }

    [Fact]
    public void Html_EscapaElContenidoVariable()
    {
        var html = Ejemplo("<a href=\"http://malo.example\">Ana</a>").Html();

        Assert.DoesNotContain("<a href=\"http://malo.example\">", html);
        Assert.Contains("&lt;a href=&quot;http://malo.example&quot;&gt;", html);
    }

    [Fact]
    public void Texto_EsLaVersionPlana_ConElEnlaceCompleto()
    {
        var texto = Ejemplo().Texto();

        Assert.DoesNotContain("<", texto);
        Assert.Contains("http://localhost:8080/?restablecer=abc", texto);
        Assert.Contains("Dispositivo: Chrome en Windows", texto);
    }

    [Fact]
    public async Task Recuperacion_EnviaElCorreoConDiseño_YTextoPlano()
    {
        await _s.Recuperacion(_testDb.CrearContexto()).SolicitarAsync(TestDb.EmailVendedor, _s.Contexto, default);

        var m = Assert.Single(_s.Correo.Enviados);
        Assert.Equal("Restablece tu contraseña", m.Asunto);
        Assert.NotNull(m.Html);
        Assert.Contains("Crear una nueva contraseña", m.Html);
        Assert.Contains("restablecer=", m.Texto);
        Assert.Contains(_s.Correo.UltimoTokenRecuperacion(), m.Html);
    }

    [Fact]
    public void Hora_SeMuestraEnHoraDeGuatemala()
    {
        Assert.Equal("01/10/2026 06:30 (hora de Guatemala)", PlantillaCorreo.Hora(new DateTime(2026, 10, 1, 12, 30, 0, DateTimeKind.Utc)));
    }
}
