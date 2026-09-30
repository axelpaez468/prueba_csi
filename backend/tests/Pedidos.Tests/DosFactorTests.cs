using Microsoft.EntityFrameworkCore;
using OtpNet;
using Pedidos.Api.Domain;
using Pedidos.Api.Errors;
using Pedidos.Api.Services;
using Pedidos.Tests.Infra;

namespace Pedidos.Tests;

public class DosFactorTests : IDisposable
{
    private readonly TestDb _testDb = new();
    private readonly ServiciosSeguridad _s = new();

    public void Dispose() => _testDb.Dispose();

    private Task<LoginResultado> Login(string email, string? tokenDispositivo = null) =>
        _s.Auth(_testDb.CrearContexto()).LoginAsync(email, TestDb.PasswordDePrueba, tokenDispositivo, _s.Contexto, default);

    private Task<Pedidos.Api.Dtos.LoginResponse?> Verificar(string desafio, string codigo, bool confiar = false) =>
        _s.Auth(_testDb.CrearContexto()).VerificarSegundoFactorAsync(desafio, codigo, confiar, _s.Contexto, default);

    /// <summary>Activa TOTP como lo haría el usuario desde "Mi seguridad" y devuelve el secreto y los códigos de respaldo.</summary>
    private async Task<(string Secreto, List<string> Respaldo)> ActivarTotp(int usuarioId)
    {
        var inicio = await _s.Cuenta(_testDb.CrearContexto()).IniciarTotpAsync(usuarioId, default);
        var codigo = new Totp(Base32Encoding.ToBytes(inicio.Secreto)).ComputeTotp();
        var respaldo = await _s.Cuenta(_testDb.CrearContexto()).ConfirmarTotpAsync(usuarioId, codigo, _s.Contexto, default);
        return (inicio.Secreto, respaldo.CodigosRespaldo);
    }

    // ---------- TOTP ----------

    [Fact]
    public async Task Totp_Activado_ElLoginPideElCodigo_YConElCodigoCorrectoEmiteLaSesion()
    {
        var (secreto, respaldo) = await ActivarTotp(TestDb.VendedorId);
        Assert.Equal(10, respaldo.Count);

        var paso1 = await Login(TestDb.EmailVendedor);
        Assert.Null(paso1.Sesion);
        Assert.Equal(MetodosDosFactor.Totp, paso1.Desafio!.Metodo);

        // Espera al siguiente intervalo: el código usado al activar no se puede reutilizar.
        var totp = new Totp(Base32Encoding.ToBytes(secreto));
        var siguiente = totp.ComputeTotp(DateTime.UtcNow.AddSeconds(30));
        Assert.NotNull(await Verificar(paso1.Desafio.Desafio, siguiente));
    }

    [Fact]
    public async Task Totp_ElMismoCodigoNoSePuedeUsarDosVeces()
    {
        var (secreto, _) = await ActivarTotp(TestDb.VendedorId);
        var codigo = new Totp(Base32Encoding.ToBytes(secreto)).ComputeTotp(DateTime.UtcNow.AddSeconds(30));

        Assert.NotNull(await Verificar((await Login(TestDb.EmailVendedor)).Desafio!.Desafio, codigo));
        Assert.Null(await Verificar((await Login(TestDb.EmailVendedor)).Desafio!.Desafio, codigo)); // replay
    }

    [Fact]
    public async Task Totp_ElSecretoSeGuardaCifrado()
    {
        var (secreto, _) = await ActivarTotp(TestDb.VendedorId);

        await using var db = _testDb.CrearContexto();
        var guardado = db.Usuarios.Single(u => u.Id == TestDb.VendedorId).TotpSecretoCifrado!;
        Assert.DoesNotContain(secreto, guardado);
        Assert.Equal(secreto, _s.Cifrador.Descifrar(guardado));
    }

    [Fact]
    public async Task Totp_ConCodigoIncorrectoAlActivar_NoSeActiva()
    {
        await _s.Cuenta(_testDb.CrearContexto()).IniciarTotpAsync(TestDb.VendedorId, default);

        await Assert.ThrowsAsync<BusinessRuleException>(() =>
            _s.Cuenta(_testDb.CrearContexto()).ConfirmarTotpAsync(TestDb.VendedorId, "000000", _s.Contexto, default));
        Assert.Equal(MetodosDosFactor.Configurar, (await Login(TestDb.EmailVendedor)).Desafio!.Metodo); // sigue sin 2FA
    }

    // ---------- Configuración obligatoria (todos los usuarios) ----------

    [Theory]
    [InlineData(TestDb.EmailAdmin)]
    [InlineData(TestDb.EmailVendedor)]
    public async Task SinAppConfigurada_ElLoginExigeConfigurarla_ConElQR(string email)
    {
        var paso1 = await Login(email);

        Assert.Null(paso1.Sesion);
        Assert.Equal(MetodosDosFactor.Configurar, paso1.Desafio!.Metodo);
        Assert.False(string.IsNullOrEmpty(paso1.Desafio.Secreto));
        Assert.StartsWith("otpauth://totp/", paso1.Desafio.Uri);
    }

    [Fact]
    public async Task Admin_ConfiguraLaAppEnElLogin_EntraYRecibeSusCodigosDeRespaldo()
    {
        var paso1 = await Login(TestDb.EmailAdmin);
        var codigo = new Totp(Base32Encoding.ToBytes(paso1.Desafio!.Secreto)).ComputeTotp();

        var sesion = await Verificar(paso1.Desafio.Desafio, codigo);

        Assert.NotNull(sesion);
        Assert.Equal(10, sesion.CodigosRespaldo!.Count);
        await using var db = _testDb.CrearContexto();
        Assert.Equal(MetodosDosFactor.Totp, db.Usuarios.Single(u => u.Id == TestDb.AdminId).DosFactor);

        // El siguiente login ya pide el código normal, no la configuración.
        Assert.Equal(MetodosDosFactor.Totp, (await Login(TestDb.EmailAdmin)).Desafio!.Metodo);
    }

    [Fact]
    public async Task Admin_ConCodigoIncorrectoAlConfigurar_NoQuedaActivado()
    {
        var paso1 = await Login(TestDb.EmailAdmin);

        Assert.Null(await Verificar(paso1.Desafio!.Desafio, "000000"));

        await using var db = _testDb.CrearContexto();
        Assert.Equal(MetodosDosFactor.Ninguno, db.Usuarios.Single(u => u.Id == TestDb.AdminId).DosFactor);
    }

    // ---------- Códigos de respaldo y dispositivo de confianza ----------

    [Fact]
    public async Task CodigoDeRespaldo_FuncionaUnaSolaVez()
    {
        var (_, respaldo) = await ActivarTotp(TestDb.VendedorId);

        Assert.NotNull(await Verificar((await Login(TestDb.EmailVendedor)).Desafio!.Desafio, respaldo[0]));
        Assert.Null(await Verificar((await Login(TestDb.EmailVendedor)).Desafio!.Desafio, respaldo[0]));
        Assert.NotNull(await Verificar((await Login(TestDb.EmailVendedor)).Desafio!.Desafio, respaldo[1].ToLower()));
    }

    [Fact]
    public async Task ConfiarEnEsteDispositivo_OmiteEl2FA_HastaCambiarLaContrasena()
    {
        var (_, respaldo) = await ActivarTotp(TestDb.VendedorId);
        var sesion = await Verificar((await Login(TestDb.EmailVendedor)).Desafio!.Desafio, respaldo[0], confiar: true);
        Assert.NotNull(sesion!.TokenDispositivo);

        Assert.NotNull((await Login(TestDb.EmailVendedor, sesion.TokenDispositivo)).Sesion); // sin 2FA

        // Cambiar la contraseña revoca los dispositivos de confianza.
        await _s.Cuenta(_testDb.CrearContexto()).CambiarPasswordAsync(
            TestDb.VendedorId, TestDb.PasswordDePrueba, "Nueva-Clave-Segura-2026", _s.Contexto, default);
        var despues = await _s.Auth(_testDb.CrearContexto())
            .LoginAsync(TestDb.EmailVendedor, "Nueva-Clave-Segura-2026", sesion.TokenDispositivo, _s.Contexto, default);
        Assert.NotNull(despues.Desafio);
    }

    // ---------- Abuso ----------

    [Fact]
    public async Task Desafio_TrasCincoCodigosErroneos_ExigeVolverAIniciarSesion()
    {
        await ActivarTotp(TestDb.VendedorId);
        var desafio = (await Login(TestDb.EmailVendedor)).Desafio!.Desafio;

        for (var i = 0; i < AuthService.IntentosPorDesafio; i++)
            Assert.Null(await Verificar(desafio, "000000"));

        await Assert.ThrowsAsync<BusinessRuleException>(() => Verificar(desafio, "000000"));
    }

    [Fact]
    public async Task Desafio_AlteradoOInventado_SeRechaza()
    {
        await Assert.ThrowsAsync<BusinessRuleException>(() => Verificar("eyJhbGciOiJub25lIn0.e30.", "123456"));
    }

    [Theory]
    [InlineData(TestDb.AdminId)]
    [InlineData(TestDb.VendedorId)]
    public async Task NingunUsuario_PuedeDesactivarEl2FA(int usuarioId)
    {
        await ActivarTotp(usuarioId);

        await Assert.ThrowsAsync<BusinessRuleException>(() =>
            _s.Cuenta(_testDb.CrearContexto()).DesactivarAsync(usuarioId, TestDb.PasswordDePrueba, _s.Contexto, default));
    }
}
