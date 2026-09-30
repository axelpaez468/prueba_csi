using System.Security.Cryptography;
using System.Text.RegularExpressions;
using Microsoft.Extensions.Caching.Memory;
using Microsoft.Extensions.Options;
using Microsoft.Extensions.Time.Testing;
using OtpNet;
using Pedidos.Api.Data;
using Pedidos.Api.Domain;
using Pedidos.Api.Dtos;
using Pedidos.Api.Notificaciones;
using Pedidos.Api.Security;
using Pedidos.Api.Services;
using Pedidos.Api.Services.Seguridad;

namespace Pedidos.Tests.Infra;

/// <summary>Correo falso: guarda los mensajes para que las pruebas lean códigos y enlaces.</summary>
public class CorreoFalso : IEnviadorCorreo
{
    public List<Mensaje> Enviados { get; } = new();

    public void Encolar(string para, string asunto, string texto) => Enviados.Add(new Mensaje(para, asunto, texto));

    public string UltimoTokenRecuperacion() =>
        Regex.Match(Enviados.Last(m => m.Asunto.Contains("Restablece")).Texto, @"restablecer=([\w-]+)").Groups[1].Value;

    public string UltimoTokenInvitacion(string para) =>
        Regex.Match(Enviados.Last(m => m.Para == para && m.Asunto.Contains("Bienvenido")).Texto, @"restablecer=([\w-]+)").Groups[1].Value;
}

public class VerificadorFiltradasFalso : IVerificadorPasswordFiltrada
{
    public HashSet<string> Filtradas { get; } = new() { "password123456", "qwertyuiop123" };

    public Task<bool> EstaFiltradaAsync(string password, CancellationToken ct) => Task.FromResult(Filtradas.Contains(password));
}

/// <summary>Arma los servicios de seguridad sobre la BD de prueba, con correo, reloj y HIBP falsos.</summary>
public sealed class ServiciosSeguridad
{
    public const string Ip = "203.0.113.10";

    // Arranca en la hora real: la validación de JWT usa el reloj del sistema. Luego se adelanta a mano.
    public FakeTimeProvider Reloj { get; } = new(DateTimeOffset.UtcNow);
    public CorreoFalso Correo { get; } = new();
    public VerificadorFiltradasFalso Filtradas { get; } = new();
    public IMemoryCache Cache { get; } = new MemoryCache(new MemoryCacheOptions { SizeLimit = 1000 });
    public Cifrador Cifrador { get; }
    public TotpService Totp { get; } = new();
    public LoginThrottle Throttle { get; }
    public ContextoCliente Contexto { get; } = new(Ip, "Mozilla/5.0 (Windows NT 10.0) Chrome/130.0");

    private readonly IOptions<JwtOptions> _jwt =
        Options.Create(new JwtOptions { Key = new string('k', JwtOptions.MinKeyBytes) });

    public ServiciosSeguridad()
    {
        Cifrador = new Cifrador(Options.Create(new SeguridadOptions
        {
            ClaveMaestra = Convert.ToBase64String(RandomNumberGenerator.GetBytes(32))
        }));
        Throttle = new LoginThrottle(Cache, Reloj);
    }

    public TokenService Tokens => new(_jwt, Reloj);

    private SegundoFactorService SegundoFactor(AppDbContext db) =>
        new(db, Cifrador, Totp, Reloj);

    public AuthService Auth(AppDbContext db) =>
        new(db, Tokens, Throttle, new BitacoraService(db, Reloj), SegundoFactor(db), Cifrador, Correo, Cache, Reloj);

    public CuentaService Cuenta(AppDbContext db) =>
        new(db, Cifrador, Totp, SegundoFactor(db), new PoliticaPassword(Filtradas), new BitacoraService(db, Reloj),
            Tokens, Correo);

    public Pedidos.Api.Services.Usuarios.UsuarioService Usuarios(AppDbContext db) =>
        new(db, Recuperacion(db), new BitacoraService(db, Reloj), Reloj);

    /// <summary>
    /// Login completo como lo haría el usuario: si es su primer ingreso, configura Google Authenticator con el
    /// secreto del QR. Devuelve null si la contraseña no es válida o si el login pide el código de una app ya configurada.
    /// </summary>
    public async Task<LoginResponse?> EntrarAsync(TestDb testDb, string email, string password,
        string? tokenDispositivo = null, bool confiar = false)
    {
        var paso1 = await Auth(testDb.CrearContexto()).LoginAsync(email, password, tokenDispositivo, Contexto, default);
        if (paso1.Sesion is not null || paso1.Desafio?.Metodo != MetodosDosFactor.Configurar) return paso1.Sesion;

        var codigo = new Totp(Base32Encoding.ToBytes(paso1.Desafio.Secreto)).ComputeTotp();
        return await Auth(testDb.CrearContexto())
            .VerificarSegundoFactorAsync(paso1.Desafio.Desafio, codigo, confiar, Contexto, default);
    }

    public RecuperacionService Recuperacion(AppDbContext db) =>
        new(db, Cifrador, new PoliticaPassword(Filtradas), new BitacoraService(db, Reloj), Correo,
            Options.Create(new FrontendOptions { UrlPublica = "http://localhost:8080" }), Reloj);
}
