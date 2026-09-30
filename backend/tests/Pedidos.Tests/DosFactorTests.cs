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

    private async Task ActivarSms(int usuarioId)
    {
        await _s.Cuenta(_testDb.CrearContexto()).IniciarSmsAsync(usuarioId, "+50255550101", default);
        await _s.Cuenta(_testDb.CrearContexto()).ConfirmarSmsAsync(usuarioId, _s.Correo.UltimoCodigoSms(), _s.Contexto, default);
        _s.Reloj.Advance(TimeSpan.FromMinutes(1)); // pasa la espera de reenvío antes del login
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
        Assert.NotNull((await Login(TestDb.EmailVendedor)).Sesion); // sigue sin 2FA
    }

    // ---------- SMS ----------

    [Fact]
    public async Task Sms_ElLoginEnviaUnCodigo_YSoloEseCodigoFunciona()
    {
        await ActivarSms(TestDb.VendedorId);

        var paso1 = await Login(TestDb.EmailVendedor);
        Assert.Equal(MetodosDosFactor.Sms, paso1.Desafio!.Metodo);
        Assert.Equal("+502 •••• 0101", paso1.Desafio.Destino);

        Assert.Null(await Verificar(paso1.Desafio.Desafio, "123456"));
        Assert.NotNull(await Verificar(paso1.Desafio.Desafio, _s.Correo.UltimoCodigoSms()));
    }

    [Fact]
    public async Task Sms_ElCodigoVenceALosCincoMinutos()
    {
        await ActivarSms(TestDb.VendedorId);
        var paso1 = await Login(TestDb.EmailVendedor);
        var codigo = _s.Correo.UltimoCodigoSms();

        _s.Reloj.Advance(TimeSpan.FromMinutes(6));

        Assert.Null(await Verificar(paso1.Desafio!.Desafio, codigo));
    }

    [Fact]
    public async Task Sms_NoSePuedeReenviarAntesDeTreintaSegundos()
    {
        await ActivarSms(TestDb.VendedorId);
        var paso1 = await Login(TestDb.EmailVendedor);

        await Assert.ThrowsAsync<BusinessRuleException>(() =>
            _s.Auth(_testDb.CrearContexto()).ReenviarCodigoSmsAsync(paso1.Desafio!.Desafio, default));

        _s.Reloj.Advance(TimeSpan.FromSeconds(31));
        await _s.Auth(_testDb.CrearContexto()).ReenviarCodigoSmsAsync(paso1.Desafio!.Desafio, default);
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

    [Fact]
    public async Task Admin_NoPuedeDesactivarEl2FA()
    {
        await ActivarSms(TestDb.AdminId);

        await Assert.ThrowsAsync<BusinessRuleException>(() =>
            _s.Cuenta(_testDb.CrearContexto()).DesactivarAsync(TestDb.AdminId, TestDb.PasswordDePrueba, _s.Contexto, default));
    }

    [Fact]
    public async Task Vendedor_PuedeDesactivarEl2FA_ConSuContrasena()
    {
        await ActivarTotp(TestDb.VendedorId);

        await Assert.ThrowsAsync<BusinessRuleException>(() =>
            _s.Cuenta(_testDb.CrearContexto()).DesactivarAsync(TestDb.VendedorId, "incorrecta", _s.Contexto, default));
        await _s.Cuenta(_testDb.CrearContexto()).DesactivarAsync(TestDb.VendedorId, TestDb.PasswordDePrueba, _s.Contexto, default);

        Assert.NotNull((await Login(TestDb.EmailVendedor)).Sesion);
        await using var db = _testDb.CrearContexto();
        Assert.Equal(0, await db.CodigosRespaldo.CountAsync(c => c.UsuarioId == TestDb.VendedorId));
    }
}
