using Pedidos.Api.Errors;
using Pedidos.Api.Services.Seguridad;
using Pedidos.Tests.Infra;

namespace Pedidos.Tests;

public class RecuperacionTests : IDisposable
{
    private const string NuevaPassword = "Otra-Clave-Muy-Segura-2026";

    private readonly TestDb _testDb = new();
    private readonly ServiciosSeguridad _s = new();

    public void Dispose() => _testDb.Dispose();

    private Task Solicitar(string email) =>
        _s.Recuperacion(_testDb.CrearContexto()).SolicitarAsync(email, _s.Contexto, default);

    private Task Restablecer(string token, string password) =>
        _s.Recuperacion(_testDb.CrearContexto()).RestablecerAsync(token, password, _s.Contexto, default);

    [Fact]
    public async Task Solicitar_ConCorreoInexistente_NoEnviaNada_NiFalla()
    {
        await Solicitar("nadie@pedidos.test");

        Assert.Empty(_s.Correo.Enviados); // la API responde igual: no revela qué correos existen
    }

    [Fact]
    public async Task Restablecer_ConElEnlaceDelCorreo_CambiaLaContrasena_YElEnlaceNoSirveDosVeces()
    {
        await Solicitar(TestDb.EmailVendedor);
        var token = _s.Correo.UltimoTokenRecuperacion();

        await Restablecer(token, NuevaPassword);

        var login = await _s.Auth(_testDb.CrearContexto()).LoginAsync(TestDb.EmailVendedor, NuevaPassword, null, _s.Contexto, default);
        Assert.NotNull(login.Sesion);
        Assert.Contains(_s.Correo.Enviados, m => m.Asunto == "Tu contraseña fue cambiada");
        await Assert.ThrowsAsync<BusinessRuleException>(() => Restablecer(token, "Tercera-Clave-Segura-2026"));
    }

    [Fact]
    public async Task Restablecer_CierraLasSesionesAbiertas()
    {
        await Solicitar(TestDb.EmailVendedor);
        await Restablecer(_s.Correo.UltimoTokenRecuperacion(), NuevaPassword);

        await using var db = _testDb.CrearContexto();
        Assert.Equal(1, db.Usuarios.Single(u => u.Id == TestDb.VendedorId).VersionSesion);
    }

    [Fact]
    public async Task Restablecer_ConEnlaceVencido_Falla()
    {
        await Solicitar(TestDb.EmailVendedor);
        var token = _s.Correo.UltimoTokenRecuperacion();

        _s.Reloj.Advance(RecuperacionService.VigenciaEnlace + TimeSpan.FromMinutes(1));

        await Assert.ThrowsAsync<BusinessRuleException>(() => Restablecer(token, NuevaPassword));
    }

    [Fact]
    public async Task PedirOtroEnlace_InvalidaElAnterior()
    {
        await Solicitar(TestDb.EmailVendedor);
        var primero = _s.Correo.UltimoTokenRecuperacion();
        await Solicitar(TestDb.EmailVendedor);

        await Assert.ThrowsAsync<BusinessRuleException>(() => Restablecer(primero, NuevaPassword));
        await Restablecer(_s.Correo.UltimoTokenRecuperacion(), NuevaPassword);
    }

    [Theory]
    [InlineData("corta1!", "al menos 12")]
    [InlineData("vendedor-2026-clave", "no debe contener tu correo")]
    [InlineData("aaaaaaaaaaaaaaa", "repetitiva")]
    [InlineData("password123456", "filtraciones")]
    public async Task Restablecer_AplicaLaPoliticaDeContrasenas(string password, string mensaje)
    {
        await Solicitar(TestDb.EmailVendedor);

        var ex = await Assert.ThrowsAsync<BusinessRuleException>(() =>
            Restablecer(_s.Correo.UltimoTokenRecuperacion(), password));

        Assert.Contains(mensaje, ex.Message);
    }

    [Fact]
    public async Task Restablecer_ConTokenInventado_Falla()
    {
        await Assert.ThrowsAsync<BusinessRuleException>(() => Restablecer("token-inventado", NuevaPassword));
    }
}
