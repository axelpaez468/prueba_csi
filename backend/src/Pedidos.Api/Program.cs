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
using Pedidos.Api.Security;
using Pedidos.Api.Services;

var builder = WebApplication.CreateBuilder(args);
var config = builder.Configuration;

// ---------- Configuración obligatoria (falla al arrancar si falta) ----------
var jwt = config.GetSection(JwtOptions.Section).Get<JwtOptions>() ?? new JwtOptions();
jwt.Validar();
builder.Services.Configure<JwtOptions>(config.GetSection(JwtOptions.Section));

var connectionString = config.GetConnectionString("Default");
if (string.IsNullOrWhiteSpace(connectionString))
    throw new InvalidOperationException("Falta la variable de entorno ConnectionStrings__Default.");

var corsOrigins = (config["Cors:AllowedOrigins"] ?? string.Empty)
    .Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
if (corsOrigins.Length == 0 || corsOrigins.Contains("*"))
    throw new InvalidOperationException("Cors:AllowedOrigins debe listar orígenes explícitos (no se permite '*').");

// ---------- Servicios ----------
builder.Services.AddDbContext<AppDbContext>(o => o.UseSqlServer(connectionString));
builder.Services.AddSingleton(TimeProvider.System);
builder.Services.AddScoped<TokenService>();
builder.Services.AddScoped<AuthService>();
builder.Services.AddScoped<PedidoService>();

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
    .WithMethods("GET", "POST")
    .WithHeaders("Authorization", "Content-Type")));

builder.Services.AddRateLimiter(o =>
{
    o.RejectionStatusCode = StatusCodes.Status429TooManyRequests;
    o.OnRejected = async (ctx, ct) =>
        await ctx.HttpContext.Response.WriteAsJsonAsync(
            new ErrorResponse("Demasiados intentos. Espere un minuto e intente de nuevo."), ct);
    o.AddPolicy(RateLimitPolicies.Login, http => RateLimitPartition.GetFixedWindowLimiter(
        http.Connection.RemoteIpAddress?.ToString() ?? "desconocido",
        _ => new FixedWindowRateLimiterOptions { PermitLimit = 10, Window = TimeSpan.FromMinutes(1) }));
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

if (app.Environment.IsDevelopment())
{
    app.UseSwagger();
    app.UseSwaggerUI();
}

app.UseCors();
app.UseAuthentication();
app.UseAuthorization();
app.UseRateLimiter();

app.MapControllers();
app.MapGet("/health", () => Results.Ok(new { status = "ok" })).AllowAnonymous().ExcludeFromDescription();

app.Run();
