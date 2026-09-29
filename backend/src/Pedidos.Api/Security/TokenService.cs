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
    private readonly JwtOptions _options;
    private readonly TimeProvider _time;

    public TokenService(IOptions<JwtOptions> options, TimeProvider time)
    {
        _options = options.Value;
        _time = time;
    }

    public LoginResponse Generar(Usuario usuario)
    {
        var expira = _time.GetUtcNow().UtcDateTime.AddMinutes(_options.ExpirationMinutes);
        var credenciales = new SigningCredentials(
            new SymmetricSecurityKey(Encoding.UTF8.GetBytes(_options.Key)), SecurityAlgorithms.HmacSha256);

        var token = new JwtSecurityToken(
            issuer: _options.Issuer,
            audience: _options.Audience,
            claims: new[]
            {
                new Claim(JwtClaims.UserId, usuario.Id.ToString()),
                new Claim(JwtClaims.Username, usuario.Username),
                new Claim(JwtClaims.Role, usuario.Rol),
                new Claim(JwtRegisteredClaimNames.Jti, Guid.NewGuid().ToString())
            },
            expires: expira,
            signingCredentials: credenciales);

        return new LoginResponse(new JwtSecurityTokenHandler().WriteToken(token), expira, usuario.Username, usuario.Rol);
    }
}
