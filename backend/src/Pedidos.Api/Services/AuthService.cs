using Microsoft.EntityFrameworkCore;
using Pedidos.Api.Data;
using Pedidos.Api.Dtos;
using Pedidos.Api.Security;

namespace Pedidos.Api.Services;

public class AuthService
{
    // Si el usuario no existe se verifica igual contra este hash, para que el tiempo de
    // respuesta no permita distinguir "usuario inexistente" de "contraseña incorrecta".
    private static readonly string HashFicticio = BCrypt.Net.BCrypt.HashPassword(Guid.NewGuid().ToString());

    private readonly AppDbContext _db;
    private readonly TokenService _tokens;

    public AuthService(AppDbContext db, TokenService tokens)
    {
        _db = db;
        _tokens = tokens;
    }

    /// <returns>El token, o null si las credenciales no son válidas.</returns>
    public async Task<LoginResponse?> LoginAsync(string username, string password, CancellationToken ct)
    {
        var usuario = await _db.Usuarios.AsNoTracking().FirstOrDefaultAsync(u => u.Username == username, ct);

        var passwordValida = BCrypt.Net.BCrypt.Verify(password, usuario?.PasswordHash ?? HashFicticio);
        if (usuario is null || !passwordValida)
            return null;

        return _tokens.Generar(usuario);
    }
}
