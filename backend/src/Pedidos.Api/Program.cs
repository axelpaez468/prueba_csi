using System.Text;
using System.Threading.RateLimiting;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Microsoft.IdentityModel.Tokens;
using Microsoft.OpenApi.Models;
using Pedidos.Api.Data;
using Pedidos.Api.Errors;
using Pedidos.Api.Notificaciones;
using Pedidos.Api.Security;
using Pedidos.Api.Services;
using Pedidos.Api.Services.Seguridad;

var builder = WebApplication.CreateBuilder(args);
var config = builder.Configuration;

// ---------- Configuración obligatoria (falla al arrancar si falta) ----------
var jwt = config.GetSection(JwtOptions.Section).Get<JwtOptions>() ?? new JwtOptions();
jwt.Validar();
builder.Services.Configure<JwtOptions>(config.GetSection(JwtOptions.Section));

(config.GetSection(SeguridadOptions.Section).Get<SeguridadOptions>() ?? new SeguridadOptions()).Validar();
builder.Services.Configure<SeguridadOptions>(config.GetSection(SeguridadOptions.Section));
builder.Services.Configure<CorreoOptions>(config.GetSection(CorreoOptions.Section));
builder.Services.Configure<SmsOptions>(config.GetSection(SmsOptions.Section));
builder.Services.Configure<FrontendOptions>(config.GetSection(FrontendOptions.Section));

var proveedorSms = config.GetSection(SmsOptions.Section).Get<SmsOptions>()?.Proveedor ?? "Simulado";
if (proveedorSms != "Simulado")
    throw new InvalidOperationException($"Proveedor de SMS no soportado: {proveedorSms}. Use 'Simulado'.");

var connectionString = config.GetConnectionString("Default");
if (string.IsNullOrWhiteSpace(connectionString))
    throw new InvalidOperationException("Falta la variable de entorno ConnectionStrings__Default.");

var corsOrigins = (config["Cors:AllowedOrigins"] ?? string.Empty)
    .Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
if (corsOrigins.Length == 0 || corsOrigins.Contains("*"))
    throw new InvalidOperationException("Cors:AllowedOrigins debe listar orígenes explícitos (no se permite '*').");

// ---------- Servidor HTTP: límites contra agotamiento de recursos ----------
builder.WebHost.ConfigureKestrel(k =>
{
    k.AddServerHeader = false;                                   // no anunciar el servidor ni su versión
    k.Limits.MaxRequestBodySize = InputLimits.CuerpoMaxBytes;    // cuerpos gigantes -> 413
    k.Limits.MaxRequestHeadersTotalSize = 16 * 1024;
    k.Limits.MaxRequestLineSize = 4 * 1024;
    k.Limits.RequestHeadersTimeout = TimeSpan.FromSeconds(10);   // slowloris: cabeceras enviadas muy lento
    k.Limits.KeepAliveTimeout = TimeSpan.FromSeconds(30);
    k.Limits.MaxConcurrentConnections = 500;
    k.Limits.MaxConcurrentUpgradedConnections = 0;              // la API no usa WebSockets
});

// ---------- Servicios ----------
builder.Services.AddDbContext<AppDbContext>(o => o.UseSqlServer(connectionString, sql => sql.CommandTimeout(15)));
builder.Services.AddSingleton(TimeProvider.System);
// Con tope de entradas: un atacante probando usuarios aleatorios no puede agotar la memoria.
builder.Services.AddMemoryCache(o => o.SizeLimit = 10_000);
builder.Services.AddSingleton<LoginThrottle>();
builder.Services.AddScoped<TokenService>();
builder.Services.AddScoped<AuthService>();
builder.Services.AddScoped<PedidoService>();

// Login de ERP: 2FA, recuperación de contraseña, bitácora y notificaciones.
builder.Services.AddSingleton<Cifrador>();
builder.Services.AddSingleton<TotpService>();
builder.Services.AddScoped<SegundoFactorService>();
builder.Services.AddScoped<BitacoraService>();
builder.Services.AddScoped<RecuperacionService>();
builder.Services.AddScoped<CuentaService>();
builder.Services.AddScoped<Pedidos.Api.Services.Usuarios.UsuarioService>();
builder.Services.AddScoped<PoliticaPassword>();
builder.Services.AddHttpClient<IVerificadorPasswordFiltrada, HibpVerificador>(c =>
{
    c.BaseAddress = new Uri("https://api.pwnedpasswords.com/");
    c.Timeout = TimeSpan.FromSeconds(3);
    c.DefaultRequestHeaders.UserAgent.ParseAdd("PedidosPruebaTecnica/1.0");
});
builder.Services.AddSingleton<ColaNotificaciones>();
builder.Services.AddSingleton<IEnviadorCorreo>(sp => sp.GetRequiredService<ColaNotificaciones>());
builder.Services.AddSingleton<IEnviadorSms, SmsSimulado>();
builder.Services.AddHostedService<ProcesadorNotificaciones>();

builder.Services.AddExceptionHandler<GlobalExceptionHandler>();
builder.Services.AddProblemDetails();

builder.Services.AddControllers()
    .ConfigureApiBehaviorOptions(o =>
    {
        // JSON mal formado o tipos incorrectos: mismo formato { "error": "..." } y sin detalles internos.
        o.InvalidModelStateResponseFactory = _ =>
            new BadRequestObjectResult(new ErrorResponse("El cuerpo de la solicitud no es válido o está mal formado."));
    });

builder.Services
    .AddAuthentication(JwtBearerDefaults.AuthenticationScheme)
    .AddJwtBearer(o =>
    {
        o.MapInboundClaims = false;
        o.TokenValidationParameters = new TokenValidationParameters
        {
            ValidateIssuer = true,
            ValidIssuer = jwt.Issuer,
            ValidateAudience = true,
            ValidAudience = jwt.Audience,
            ValidateIssuerSigningKey = true,
            IssuerSigningKey = new SymmetricSecurityKey(Encoding.UTF8.GetBytes(jwt.Key)),
            ValidAlgorithms = new[] { SecurityAlgorithms.HmacSha256 },
            ValidateLifetime = true,
            ClockSkew = TimeSpan.FromSeconds(30),
            NameClaimType = JwtClaims.Username,
            RoleClaimType = JwtClaims.Role
        };
        o.Events = new JwtBearerEvents
        {
            // Un token emitido antes de cambiar la contraseña (o desactivar el 2FA) deja de ser válido:
            // así "cerrar las demás sesiones" funciona aunque el JWT en sí no haya expirado.
            OnTokenValidated = async ctx =>
            {
                var sub = ctx.Principal?.FindFirst(JwtClaims.UserId)?.Value;
                var sv = ctx.Principal?.FindFirst(JwtClaims.VersionSesion)?.Value;
                if (!int.TryParse(sub, out var id) || !int.TryParse(sv, out var version))
                {
                    ctx.Fail("Token sin versión de sesión.");
                    return;
                }
                var db = ctx.HttpContext.RequestServices.GetRequiredService<AppDbContext>();
                var actual = await db.Usuarios.Where(u => u.Id == id).Select(u => (int?)u.VersionSesion)
                    .FirstOrDefaultAsync(ctx.HttpContext.RequestAborted);
                if (actual != version)
                    ctx.Fail("La sesión fue cerrada.");
            },
            OnChallenge = async ctx =>
            {
                ctx.HandleResponse();
                ctx.Response.StatusCode = StatusCodes.Status401Unauthorized;
                await ctx.Response.WriteAsJsonAsync(new ErrorResponse("Sesión no válida o expirada. Inicie sesión de nuevo."));
            },
            OnForbidden = async ctx =>
            {
                ctx.Response.StatusCode = StatusCodes.Status403Forbidden;
                await ctx.Response.WriteAsJsonAsync(new ErrorResponse("No tiene permisos para realizar esta operación."));
            }
        };
    });

// Seguro por defecto: todo endpoint exige autenticación salvo que se marque [AllowAnonymous].
builder.Services.AddAuthorization(o =>
    o.FallbackPolicy = new AuthorizationPolicyBuilder().RequireAuthenticatedUser().Build());

builder.Services.AddCors(o => o.AddDefaultPolicy(p => p
    .WithOrigins(corsOrigins)
    .WithMethods("GET", "POST", "PUT", "DELETE")
    .WithHeaders("Authorization", "Content-Type")));

builder.Services.AddRateLimiter(o =>
{
    o.RejectionStatusCode = StatusCodes.Status429TooManyRequests;
    o.OnRejected = async (ctx, ct) =>
    {
        if (ctx.Lease.TryGetMetadata(MetadataName.RetryAfter, out var espera))
            ctx.HttpContext.Response.Headers.RetryAfter = ((int)Math.Ceiling(espera.TotalSeconds)).ToString();
        await ctx.HttpContext.Response.WriteAsJsonAsync(
            new ErrorResponse("Demasiadas solicitudes. Espere un momento e intente de nuevo."), ct);
    };
    // Capas: límite global por IP (toda la API) + límites específicos más estrictos por endpoint.
    o.GlobalLimiter = PartitionedRateLimiter.Create<HttpContext, string>(RateLimitPolicies.Global);
    o.AddPolicy(RateLimitPolicies.Login, RateLimitPolicies.PorIpLogin);
    o.AddPolicy(RateLimitPolicies.CrearPedido, RateLimitPolicies.PorUsuarioPedidos);
    o.AddPolicy(RateLimitPolicies.SegundoFactor, RateLimitPolicies.PorIpSegundoFactor);
    o.AddPolicy(RateLimitPolicies.Recuperacion, RateLimitPolicies.PorIpRecuperacion);
});

builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen(o =>
{
    o.SwaggerDoc("v1", new OpenApiInfo { Title = "Pedidos API", Version = "v1" });
    var esquema = new OpenApiSecurityScheme
    {
        Name = "Authorization",
        Type = SecuritySchemeType.Http,
        Scheme = "bearer",
        BearerFormat = "JWT",
        In = ParameterLocation.Header,
        Reference = new OpenApiReference { Type = ReferenceType.SecurityScheme, Id = "Bearer" }
    };
    o.AddSecurityDefinition("Bearer", esquema);
    o.AddSecurityRequirement(new OpenApiSecurityRequirement { [esquema] = Array.Empty<string>() });
});

// ---------- Pipeline ----------
var app = builder.Build();

app.UseExceptionHandler();
app.UseSecurityHeaders();

if (app.Environment.IsDevelopment())
{
    app.UseSwagger();
    app.UseSwaggerUI();
}
else
{
    // Solo se envía en respuestas HTTPS (TLS terminado en el proxy/balanceador de producción).
    app.UseHsts();
}

app.UseCors();
app.UseAuthentication();
// Después de autenticar (para limitar por usuario) y antes de autorizar y ejecutar el endpoint:
// las peticiones rechazadas no llegan a tocar la base de datos.
app.UseRateLimiter();
app.UseAuthorization();

app.MapControllers();
app.MapGet("/health", () => Results.Ok(new { status = "ok" })).AllowAnonymous().ExcludeFromDescription();

app.Run();
