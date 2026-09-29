using Microsoft.EntityFrameworkCore;
using Pedidos.Api.Data;
using Pedidos.Api.Dtos;
using Pedidos.Api.Security;

namespace Pedidos.Api.Services;

/// <summary>Resultado del login: sesión emitida, credenciales inválidas o cuenta bloqueada temporalmente.</summary>
public record LoginResultado(LoginResponse? Sesion, TimeSpan? BloqueadoPor)
{
    public static LoginResultado Invalido => new(null, null);
}

public class AuthService
{
    // Si el usuario no existe se verifica igual contra este hash, para que el tiempo de
    // respuesta no permita distinguir "usuario inexistente" de "contraseña incorrecta".
    private static readonly string HashFicticio = BCrypt.Net.BCrypt.HashPassword(Guid.NewGuid().ToString());

    private readonly AppDbContext _db;
    private readonly TokenService _tokens;
    private readonly LoginThrottle _throttle;

    public AuthService(AppDbContext db, TokenService tokens, LoginThrottle throttle)
    {
        _db = db;
        _tokens = tokens;
        _throttle = throttle;
    }

    public async Task<LoginResultado> LoginAsync(string username, string password, CancellationToken ct)
    {
        // Con la cuenta bloqueada ni siquiera se verifica la contraseña: así la fuerza bruta no avanza.
        var bloqueo = _throttle.TiempoBloqueo(username);
        if (bloqueo is not null)
            return new LoginResultado(null, bloqueo);

        // Consulta LINQ: EF Core la envía parametrizada (@username), nunca concatenada.
        var usuario = await _db.Usuarios.AsNoTracking().FirstOrDefaultAsync(u => u.Username == username, ct);

        var passwordValida = BCrypt.Net.BCrypt.Verify(password, usuario?.PasswordHash ?? HashFicticio);
        if (usuario is null || !passwordValida)
        {
            _throttle.RegistrarFallo(username);
            return LoginResultado.Invalido;
        }

        _throttle.RegistrarExito(username);
        return new LoginResultado(_tokens.Generar(usuario), null);
    }
}
