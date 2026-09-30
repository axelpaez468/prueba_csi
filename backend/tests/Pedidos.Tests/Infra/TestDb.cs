using Microsoft.Data.Sqlite;
using Microsoft.EntityFrameworkCore;
using Pedidos.Api.Data;
using Pedidos.Api.Domain;

namespace Pedidos.Tests.Infra;

/// <summary>
/// Base de datos SQLite en memoria por prueba. A diferencia del proveedor InMemory de EF,
/// SQLite soporta transacciones reales, ExecuteUpdate y check constraints.
/// </summary>
public sealed class TestDb : IDisposable
{
    private readonly SqliteConnection _connection;

    public const int VendedorId = 1;
    public const int OtroVendedorId = 2;
    public const int AdminId = 3;

    public TestDb()
    {
        _connection = new SqliteConnection("DataSource=:memory:");
        _connection.Open();

        using var db = CrearContexto();
        db.Database.EnsureCreated();
        Sembrar(db);
    }

    public AppDbContext CrearContexto() =>
        new(new DbContextOptionsBuilder<AppDbContext>().UseSqlite(_connection).Options);

    private static void Sembrar(AppDbContext db)
    {
        db.Usuarios.AddRange(UsuariosSemilla());
        db.Productos.AddRange(ProductosSemilla());
        db.SaveChanges();
    }

    // Los Ids se dejan a la BD (IDENTITY en SQL Server); al insertarse en este orden quedan 1..N.
    public const string EmailVendedor = "vendedor@pedidos.test";
    public const string EmailAdmin = "admin@pedidos.test";

    public static List<Usuario> UsuariosSemilla() => new()
    {
        new Usuario { Username = "vendedor", Email = EmailVendedor, PasswordHash = HashDePrueba, Rol = Roles.Vendedor }, // VendedorId
        new Usuario { Username = "vendedor2", Email = "vendedor2@pedidos.test", PasswordHash = HashDePrueba, Rol = Roles.Vendedor }, // OtroVendedorId
        new Usuario { Username = "admin", Email = EmailAdmin, PasswordHash = HashDePrueba, Rol = Roles.Admin } // AdminId
    };

    public static List<Producto> ProductosSemilla() => new()
    {
        new Producto { Codigo = "P001", Nombre = "Teclado", Precio = 150.00m, Stock = 10 },
        new Producto { Codigo = "P002", Nombre = "Mouse", Precio = 75.50m, Stock = 5 },
        new Producto { Codigo = "P003", Nombre = "Monitor", Precio = 1200.00m, Stock = 1 }
    };

    public const string PasswordDePrueba = "Clave-de-prueba-1";

    // Work factor bajo solo para que las pruebas sean rápidas.
    public static readonly string HashDePrueba = BCrypt.Net.BCrypt.HashPassword(PasswordDePrueba, workFactor: 4);

    public int StockDe(int productoId)
    {
        using var db = CrearContexto();
        return db.Productos.AsNoTracking().Single(p => p.Id == productoId).Stock;
    }

    public int CantidadPedidos()
    {
        using var db = CrearContexto();
        return db.Pedidos.Count();
    }

    public void Dispose() => _connection.Dispose();
}
