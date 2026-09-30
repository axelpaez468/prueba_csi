using System.IdentityModel.Tokens.Jwt;
using System.Security.Claims;
using System.Text;
using Microsoft.Extensions.Options;
using Microsoft.IdentityModel.Tokens;
using Pedidos.Api.Domain;
using Pedidos.Api.Dtos;

namespace Pedidos.Api.Security;

public class TokenService
{
    /// <summary>Vida del desafío de 2FA: tiempo para escribir el código tras la contraseña.</summary>
    public static readonly TimeSpan DuracionDesafio = TimeSpan.FromMinutes(5);

    private readonly JwtOptions _options;
    private readonly TimeProvider _time;
    private readonly SymmetricSecurityKey _clave;

    public TokenService(IOptions<JwtOptions> options, TimeProvider time)
    {
        _options = options.Value;
        _time = time;
        _clave = new SymmetricSecurityKey(Encoding.UTF8.GetBytes(_options.Key));
    }

    /// <summary>Audiencia distinta: un desafío de 2FA nunca es aceptado como token de sesión.</summary>
    private string AudienciaDesafio => _options.Audience + ".2fa";

    public LoginResponse Generar(Usuario usuario, string? tokenDispositivo = null)
    {
        var expira = _time.GetUtcNow().UtcDateTime.AddMinutes(_options.ExpirationMinutes);
        var token = Escribir(_options.Audience, expira, new[]
        {
            new Claim(JwtClaims.UserId, usuario.Id.ToString()),
            new Claim(JwtClaims.Username, usuario.Username),
            new Claim(JwtClaims.Email, usuario.Email),
            new Claim(JwtClaims.Role, usuario.Rol),
            new Claim(JwtClaims.VersionSesion, usuario.VersionSesion.ToString())
        });
        return new LoginResponse(token, expira, usuario.Username, usuario.Email, usuario.Rol, tokenDispositivo);
    }

    public string GenerarDesafio(Usuario usuario) =>
        Escribir(AudienciaDesafio, _time.GetUtcNow().UtcDateTime.Add(DuracionDesafio), new[]
        {
            new Claim(JwtClaims.UserId, usuario.Id.ToString()),
            new Claim(JwtClaims.VersionSesion, usuario.VersionSesion.ToString())
        });

    /// <returns>(id de usuario, id único del desafío), o null si es inválido o expiró.</returns>
    public (int UsuarioId, string DesafioId, int VersionSesion)? ValidarDesafio(string? desafio)
    {
        if (string.IsNullOrWhiteSpace(desafio)) return null;
        try
        {
            var principal = new JwtSecurityTokenHandler { MapInboundClaims = false }.ValidateToken(desafio,
                new TokenValidationParameters
                {
                    ValidIssuer = _options.Issuer,
                    ValidAudience = AudienciaDesafio,
                    IssuerSigningKey = _clave,
                    ValidAlgorithms = new[] { SecurityAlgorithms.HmacSha256 },
                    ClockSkew = TimeSpan.FromSeconds(10)
                }, out _);
            return (int.Parse(principal.FindFirst(JwtClaims.UserId)!.Value),
                principal.FindFirst(JwtRegisteredClaimNames.Jti)!.Value,
                int.Parse(principal.FindFirst(JwtClaims.VersionSesion)!.Value));
        }
        catch (Exception ex) when (ex is SecurityTokenException or ArgumentException or FormatException)
        {
            return null;
        }
    }

    private string Escribir(string audiencia, DateTime expira, IEnumerable<Claim> claims) =>
        new JwtSecurityTokenHandler().WriteToken(new JwtSecurityToken(
            issuer: _options.Issuer,
            audience: audiencia,
            claims: claims.Append(new Claim(JwtRegisteredClaimNames.Jti, Guid.NewGuid().ToString())),
            expires: expira,
            signingCredentials: new SigningCredentials(_clave, SecurityAlgorithms.HmacSha256)));
}
