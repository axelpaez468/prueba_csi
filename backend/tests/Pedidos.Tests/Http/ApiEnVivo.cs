using System.Collections.Concurrent;
using System.Diagnostics;
using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Net.Sockets;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using Microsoft.Data.SqlClient;
using Microsoft.EntityFrameworkCore;
using MimeKit;
using OtpNet;
using Pedidos.Api.Data;
using Pedidos.Api.Domain;
using Pedidos.Tests.Infra;

namespace Pedidos.Tests.Http;

/// <summary>
/// La API real corriendo como proceso aparte (Kestrel, middleware, JWT, límites de peticiones y SQL Server),
/// sobre una base de datos nueva que se borra al terminar. El correo y el servicio de contraseñas filtradas
/// se reemplazan por servidores locales simulados, así las pruebas no dependen de internet.
/// Se activa con la misma variable que las pruebas de concurrencia (<see cref="SqlServerFactAttribute"/>).
/// </summary>
public sealed class ApiEnVivo : IAsyncLifetime
{
    public const string PasswordFiltrada = "Contraseña-Filtrada-2026";

    public static readonly JsonSerializerOptions Json = new(JsonSerializerDefaults.Web);

    private readonly string _baseDatos = $"PedidosHttp_{Guid.NewGuid():N}";
    private Process? _api;
    private readonly StringBuilder _salida = new();
    private TcpListener? _smtp;
    private TcpListener? _hibp;
    private readonly CancellationTokenSource _fin = new();
    private int _siguienteIp = 10;

    /// <summary>Correos que la API envió (los atrapa el SMTP simulado).</summary>
    public ConcurrentQueue<MimeMessage> Correos { get; } = new();

    /// <summary>Secreto de Google Authenticator y último paso usado de cada usuario que ya entró.</summary>
    private readonly ConcurrentDictionary<string, (string Secreto, long UltimoPaso)> _totp = new();
    private readonly ConcurrentDictionary<string, string> _tokens = new();

    public Uri Base { get; private set; } = null!;

    /// <summary>Clave con que la API firma los tokens (para fabricar tokens alterados en las pruebas).</summary>
    public string JwtKey { get; } = Convert.ToBase64String(RandomNumberGenerator.GetBytes(48));
    public string ConnectionString { get; private set; } = "";
    public bool Disponible => !string.IsNullOrWhiteSpace(SqlServerFactAttribute.ConnectionString);

    public static class Correo
    {
        public const string Vendedor = TestDb.EmailVendedor;
        public const string Vendedor2 = "vendedor2@pedidos.test";
        public const string Admin = TestDb.EmailAdmin;
        public const string Bodega = "bodega@pedidos.test";
        public const string Compras = "compras@pedidos.test";
        public const string Contador = "contador@pedidos.test";

        public static string De(string rol) => rol switch
        {
            Roles.Vendedor => Vendedor,
            Roles.Admin => Admin,
            Roles.Bodega => Bodega,
            Roles.Compras => Compras,
            Roles.Contador => Contador,
            _ => throw new ArgumentOutOfRangeException(nameof(rol))
        };
    }

    public async Task InitializeAsync()
    {
        if (!Disponible) return;

        // 1. Base de datos nueva con los datos de las pruebas.
        ConnectionString = new SqlConnectionStringBuilder(SqlServerFactAttribute.ConnectionString) { InitialCatalog = _baseDatos }
            .ConnectionString;
        await using (var db = new AppDbContext(new DbContextOptionsBuilder<AppDbContext>().UseSqlServer(ConnectionString).Options))
        {
            await db.Database.EnsureCreatedAsync();
            TestDb.Sembrar(db);
            db.Usuarios.AddRange(
                Usuario("Bodega", "Central", Correo.Bodega, "BOD-0001", Roles.Bodega),
                Usuario("Compras", "Central", Correo.Compras, "COM-0001", Roles.Compras),
                Usuario("Contador", "General", Correo.Contador, "CON-0001", Roles.Contador));
            await db.SaveChangesAsync();
        }

        // 2. Servidores simulados.
        _smtp = Escuchar(AtenderSmtp);
        _hibp = Escuchar(AtenderHibp);

        // 3. La API, como en producción pero apuntando a lo anterior.
        var puerto = PuertoLibre();
        Base = new Uri($"http://127.0.0.1:{puerto}/");
        var dll = RutaApi();
        var inicio = new ProcessStartInfo("dotnet", $"\"{dll}\"")
        {
            WorkingDirectory = Path.GetDirectoryName(dll)!,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            UseShellExecute = false,
            CreateNoWindow = true
        };
        var env = inicio.Environment;
        env["ASPNETCORE_URLS"] = Base.ToString();
        env["ASPNETCORE_ENVIRONMENT"] = "Production";
        env["ConnectionStrings__Default"] = ConnectionString;
        env["Jwt__Key"] = JwtKey;
        env["Seguridad__ClaveMaestra"] = Convert.ToBase64String(RandomNumberGenerator.GetBytes(32));
        env["Seguridad__PwnedPasswordsUrl"] = $"http://127.0.0.1:{((IPEndPoint)_hibp.LocalEndpoint).Port}/";
        env["Cors__AllowedOrigins"] = "http://localhost:8080";
        env["Frontend__UrlPublica"] = "http://localhost:8080";
        env["Demo__Generar"] = "false";
        env["Correo__Host"] = "127.0.0.1";
        env["Correo__Puerto"] = ((IPEndPoint)_smtp.LocalEndpoint).Port.ToString();
        env["Correo__Tls"] = "None";
        env["Logging__LogLevel__Default"] = "Warning";

        _api = Process.Start(inicio)!;
        _api.OutputDataReceived += (_, e) => Registrar(e.Data);
        _api.ErrorDataReceived += (_, e) => Registrar(e.Data);
        _api.BeginOutputReadLine();
        _api.BeginErrorReadLine();

        using var http = new HttpClient { BaseAddress = Base };
        var limite = DateTime.UtcNow.AddSeconds(60);
        while (true)
        {
            if (_api.HasExited) throw new InvalidOperationException("La API no arrancó:\n" + Salida);
            try
            {
                if ((await http.GetAsync("health")).IsSuccessStatusCode) break;
            }
            catch (HttpRequestException) { }
            if (DateTime.UtcNow > limite) throw new TimeoutException("La API no respondió /health:\n" + Salida);
            await Task.Delay(250);
        }
    }

    public async Task DisposeAsync()
    {
        _fin.Cancel();
        _smtp?.Stop();
        _hibp?.Stop();
        if (_api is { HasExited: false })
        {
            _api.Kill(entireProcessTree: true);
            await _api.WaitForExitAsync();
        }
        if (!Disponible) return;
        SqlConnection.ClearAllPools();
        await using var cn = new SqlConnection(SqlServerFactAttribute.ConnectionString);
        await cn.OpenAsync();
        await using var cmd = new SqlCommand(
            $"IF DB_ID('{_baseDatos}') IS NOT NULL BEGIN ALTER DATABASE [{_baseDatos}] SET SINGLE_USER WITH ROLLBACK IMMEDIATE; DROP DATABASE [{_baseDatos}]; END",
            cn);
        await cmd.ExecuteNonQueryAsync();
    }

    public string Salida
    {
        get { lock (_salida) return _salida.ToString(); }
    }

    private void Registrar(string? linea)
    {
        if (linea is null) return;
        lock (_salida)
        {
            if (_salida.Length < 200_000) _salida.AppendLine(linea);
        }
    }

    /// <summary>Usuario nuevo, solo para una prueba (para no afectar a los que comparten las demás).</summary>
    public async Task<(int Id, string Email)> CrearUsuarioAsync(string rol)
    {
        var codigo = Guid.NewGuid().ToString("N")[..8].ToUpperInvariant();
        var email = $"u{codigo.ToLowerInvariant()}@pedidos.test";
        await using var db = Db();
        var u = Usuario("Prueba", "Temporal", email, "TMP-" + codigo, rol);
        db.Usuarios.Add(u);
        await db.SaveChangesAsync();
        return (u.Id, email);
    }

    /// <summary>Contexto directo a la base de la prueba (para preparar casos o revisar resultados).</summary>
    public AppDbContext Db() => new(new DbContextOptionsBuilder<AppDbContext>().UseSqlServer(ConnectionString).Options);

    // ---------------------------------------------------------------- clientes

    /// <summary>
    /// Cliente HTTP con su propia IP de origen (127.0.0.x). Los límites de peticiones son por IP: así cada prueba
    /// tiene su propio cupo, como usuarios en computadoras distintas.
    /// </summary>
    public HttpClient Cliente(string? token = null)
    {
        var n = Interlocked.Increment(ref _siguienteIp);
        var ip = IPAddress.Parse($"127.0.{n / 250}.{n % 250 + 2}");
        var handler = new SocketsHttpHandler
        {
            ConnectCallback = async (ctx, ct) =>
            {
                var socket = new Socket(AddressFamily.InterNetwork, SocketType.Stream, ProtocolType.Tcp) { NoDelay = true };
                try
                {
                    socket.Bind(new IPEndPoint(ip, 0));
                    await socket.ConnectAsync(ctx.DnsEndPoint, ct);
                    return new NetworkStream(socket, ownsSocket: true);
                }
                catch
                {
                    socket.Dispose();
                    throw;
                }
            }
        };
        var http = new HttpClient(handler) { BaseAddress = Base, Timeout = TimeSpan.FromSeconds(60) };
        if (token is not null) http.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", token);
        return http;
    }

    /// <summary>Token de sesión del usuario del rol (entra una vez, con Google Authenticator, y se reutiliza).</summary>
    public async Task<string> TokenAsync(string rol) =>
        _tokens.TryGetValue(rol, out var t) ? t : _tokens[rol] = await EntrarAsync(Correo.De(rol), TestDb.PasswordDePrueba);

    public async Task<HttpClient> ComoAsync(string rol) => Cliente(await TokenAsync(rol));

    /// <summary>
    /// Sesión de un usuario nuevo del rol. Para pruebas que hacen muchas ventas: el límite de 20 ventas por minuto
    /// es por usuario y el vendedor compartido se agotaría.
    /// </summary>
    public async Task<HttpClient> ComoNuevoAsync(string rol)
    {
        var (_, email) = await CrearUsuarioAsync(rol);
        return Cliente(await EntrarAsync(email, TestDb.PasswordDePrueba));
    }

    /// <summary>Olvida el token guardado del rol (después de una prueba que cierra sus sesiones).</summary>
    public void OlvidarToken(string rol) => _tokens.TryRemove(rol, out _);

    /// <summary>Inicio de sesión completo: contraseña y código de Google Authenticator (lo configura la primera vez).</summary>
    public async Task<string> EntrarAsync(string email, string password)
    {
        using var http = Cliente();
        var r = await http.PostAsJsonAsync("api/auth/login", new { email, password });
        var cuerpo = await r.Content.ReadAsStringAsync();
        if (r.StatusCode != HttpStatusCode.OK) throw new InvalidOperationException($"Login {email}: {(int)r.StatusCode} {cuerpo}");
        using var doc = JsonDocument.Parse(cuerpo);
        var raiz = doc.RootElement;
        if (raiz.TryGetProperty("token", out var directo)) return directo.GetString()!;

        if (raiz.TryGetProperty("secreto", out var s) && s.GetString() is { } secreto)
            _totp[email] = (secreto, 0);
        var codigo = CodigoTotp(email);
        var v = await http.PostAsJsonAsync("api/auth/login/verificar", new { desafio = raiz.GetProperty("desafio").GetString(), codigo });
        var cuerpoV = await v.Content.ReadAsStringAsync();
        if (v.StatusCode != HttpStatusCode.OK) throw new InvalidOperationException($"Verificar {email}: {(int)v.StatusCode} {cuerpoV}");
        return JsonDocument.Parse(cuerpoV).RootElement.GetProperty("token").GetString()!;
    }

    /// <summary>
    /// Código de Google Authenticator que la API acepta: del intervalo actual o del siguiente (la API rechaza un
    /// intervalo ya usado, así que dos inicios de sesión seguidos del mismo usuario usan intervalos distintos).
    /// </summary>
    public string CodigoTotp(string email)
    {
        var (secreto, ultimo) = _totp[email];
        var totp = new Totp(Base32Encoding.ToBytes(secreto));
        long ahora, paso;
        // El actual o el siguiente (nunca el anterior: si el reloj cambia de intervalo antes de que llegue la
        // petición, dejaría de valer). Si ya se usaron los dos, espera al próximo intervalo.
        while ((paso = Math.Max(ahora = DateTimeOffset.UtcNow.ToUnixTimeSeconds() / 30, ultimo + 1)) > ahora + 1)
            Thread.Sleep(1000);
        _totp[email] = (secreto, paso);
        return totp.ComputeTotp(DateTimeOffset.FromUnixTimeSeconds(paso * 30).UtcDateTime);
    }

    // ---------------------------------------------------------------- correo

    /// <summary>Espera el último correo para la dirección (lo envía la cola de la API en segundo plano).</summary>
    public async Task<MimeMessage> CorreoParaAsync(string email, string asunto, TimeSpan? espera = null)
    {
        var limite = DateTime.UtcNow + (espera ?? TimeSpan.FromSeconds(20));
        while (DateTime.UtcNow < limite)
        {
            var m = Correos.LastOrDefault(c => c.To.Mailboxes.Any(x => x.Address.Equals(email, StringComparison.OrdinalIgnoreCase))
                                               && c.Subject == asunto);
            if (m is not null) return m;
            await Task.Delay(200);
        }
        throw new TimeoutException($"No llegó el correo \"{asunto}\" a {email}. Recibidos: " +
                                   string.Join(", ", Correos.Select(c => $"{c.To} «{c.Subject}»")));
    }

    /// <summary>Token del enlace "?restablecer=..." de un correo.</summary>
    public static string TokenDelEnlace(MimeMessage correo)
    {
        var texto = correo.TextBody ?? "";
        var i = texto.IndexOf("restablecer=", StringComparison.Ordinal);
        if (i < 0) throw new InvalidOperationException("El correo no trae enlace:\n" + texto);
        var token = new string(texto[(i + "restablecer=".Length)..].TakeWhile(c => char.IsLetterOrDigit(c) || c is '-' or '_').ToArray());
        return token;
    }

    // ---------------------------------------------------------------- infraestructura

    private static Usuario Usuario(string nombre, string apellido, string email, string codigo, string rol) => new()
    {
        Nombre = nombre,
        Apellido = apellido,
        Username = $"{nombre} {apellido}",
        Email = email,
        CodigoCorporativo = codigo,
        Telefono = "+50255550199",
        PasswordHash = TestDb.HashDePrueba,
        Rol = rol,
        CreadoEn = DateTime.UtcNow
    };

    private static int PuertoLibre()
    {
        var l = new TcpListener(IPAddress.Loopback, 0);
        l.Start();
        var p = ((IPEndPoint)l.LocalEndpoint).Port;
        l.Stop();
        return p;
    }

    private static string RutaApi()
    {
        // tests/Pedidos.Tests/bin/<Config>/net8.0 → src/Pedidos.Api/bin/<Config>/net8.0/Pedidos.Api.dll
        var aqui = new DirectoryInfo(AppContext.BaseDirectory.TrimEnd(Path.DirectorySeparatorChar));
        var tfm = aqui.Name;
        var config = aqui.Parent!.Name;
        var raiz = aqui.Parent.Parent!.Parent!.Parent!.Parent!.FullName; // backend/
        var dll = Path.Combine(raiz, "src", "Pedidos.Api", "bin", config, tfm, "Pedidos.Api.dll");
        return File.Exists(dll) ? dll : throw new FileNotFoundException("Compila la API antes de las pruebas HTTP.", dll);
    }

    private TcpListener Escuchar(Func<TcpClient, Task> atender)
    {
        var l = new TcpListener(IPAddress.Loopback, 0);
        l.Start();
        _ = Task.Run(async () =>
        {
            while (!_fin.IsCancellationRequested)
            {
                TcpClient c;
                try { c = await l.AcceptTcpClientAsync(_fin.Token); }
                catch { return; }
                _ = Task.Run(async () =>
                {
                    using (c)
                    {
                        try { await atender(c); }
                        catch (Exception ex) { Registrar("[simulador] " + ex.Message); }
                    }
                });
            }
        });
        return l;
    }

    /// <summary>SMTP mínimo: acepta todo y guarda el mensaje.</summary>
    private async Task AtenderSmtp(TcpClient c)
    {
        var stream = c.GetStream();
        var lector = new StreamReader(stream, Encoding.Latin1);
        var escritor = new StreamWriter(stream, Encoding.ASCII) { NewLine = "\r\n", AutoFlush = true };
        await escritor.WriteLineAsync("220 simulador ESMTP");
        while (await lector.ReadLineAsync() is { } linea)
        {
            var cmd = linea.Length >= 4 ? linea[..4].ToUpperInvariant() : linea.ToUpperInvariant();
            switch (cmd)
            {
                case "EHLO":
                    await escritor.WriteLineAsync("250-simulador");
                    await escritor.WriteLineAsync("250 8BITMIME");
                    break;
                case "DATA":
                    await escritor.WriteLineAsync("354 fin con <CRLF>.<CRLF>");
                    var datos = new StringBuilder();
                    while (await lector.ReadLineAsync() is { } l && l != ".")
                        datos.Append(l.StartsWith("..") ? l[1..] : l).Append("\r\n");
                    Correos.Enqueue(MimeMessage.Load(new MemoryStream(Encoding.Latin1.GetBytes(datos.ToString()))));
                    await escritor.WriteLineAsync("250 OK");
                    break;
                case "QUIT":
                    await escritor.WriteLineAsync("221 adiós");
                    return;
                default:
                    await escritor.WriteLineAsync("250 OK");
                    break;
            }
        }
    }

    /// <summary>"Pwned Passwords" simulado: solo <see cref="PasswordFiltrada"/> aparece como filtrada.</summary>
    private static async Task AtenderHibp(TcpClient c)
    {
        var stream = c.GetStream();
        var lector = new StreamReader(stream, Encoding.ASCII);
        var primera = await lector.ReadLineAsync() ?? "";
        while (!string.IsNullOrEmpty(await lector.ReadLineAsync())) { }

        var sha1 = Convert.ToHexString(SHA1.HashData(Encoding.UTF8.GetBytes(PasswordFiltrada)));
        var prefijo = primera.Split(' ').ElementAtOrDefault(1)?.Split('/').LastOrDefault() ?? "";
        var cuerpo = prefijo.Equals(sha1[..5], StringComparison.OrdinalIgnoreCase)
            ? $"{sha1[5..]}:1234\r\n0000000000000000000000000000000000A:0"
            : "0000000000000000000000000000000000A:0";
        var bytes = Encoding.ASCII.GetBytes(cuerpo);
        var cabecera = Encoding.ASCII.GetBytes(
            $"HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nContent-Length: {bytes.Length}\r\nConnection: close\r\n\r\n");
        await stream.WriteAsync(cabecera);
        await stream.WriteAsync(bytes);
    }
}

/// <summary>Una sola API para todas las clases de pruebas HTTP (arrancarla toma unos segundos).</summary>
[CollectionDefinition(Nombre)]
public sealed class ApiColeccion : ICollectionFixture<ApiEnVivo>
{
    public const string Nombre = "API en vivo";
}

/// <summary>Igual que <see cref="SqlServerFactAttribute"/>: sin SQL Server configurado, la prueba se omite.</summary>
public sealed class ApiFactAttribute : FactAttribute
{
    public ApiFactAttribute()
    {
        if (string.IsNullOrWhiteSpace(SqlServerFactAttribute.ConnectionString))
            Skip = $"Defina {SqlServerFactAttribute.Variable} para ejecutar las pruebas HTTP contra la API real.";
    }
}

public sealed class ApiTheoryAttribute : TheoryAttribute
{
    public ApiTheoryAttribute()
    {
        if (string.IsNullOrWhiteSpace(SqlServerFactAttribute.ConnectionString))
            Skip = $"Defina {SqlServerFactAttribute.Variable} para ejecutar las pruebas HTTP contra la API real.";
    }
}
