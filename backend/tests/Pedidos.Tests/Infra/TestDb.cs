using Microsoft.Data.Sqlite;
using Microsoft.EntityFrameworkCore;
using Pedidos.Api.Data;
using Pedidos.Api.Domain;
using Pedidos.Api.Services;
using Pedidos.Api.Services.Erp;

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

    /// <summary>Cliente "CF" (consumidor final), el primero que se siembra.</summary>
    public const int ConsumidorFinalId = 1;

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

    /// <summary>Mismos datos base que db/init/init.sql: usuarios, productos, consumidor final y catálogo de cuentas.</summary>
    public static void Sembrar(AppDbContext db)
    {
        db.Usuarios.AddRange(UsuariosSemilla());
        db.Productos.AddRange(ProductosSemilla());
        db.Clientes.Add(new Cliente { Nit = Cliente.NitConsumidorFinal, Nombre = "Consumidor Final", CreadoEn = DateTime.UtcNow });
        db.CuentasContables.AddRange(CuentasSemilla());
        db.SaveChanges();
    }

    /// <summary>Servicio de ventas con su contabilidad, sobre el contexto indicado.</summary>
    public static PedidoService Ventas(AppDbContext db, TimeProvider? reloj = null)
    {
        var tiempo = reloj ?? TimeProvider.System;
        return new PedidoService(db, tiempo, new ContabilidadService(db, tiempo));
    }

    // Los Ids se dejan a la BD (IDENTITY en SQL Server); al insertarse en este orden quedan 1..N.
    public const string EmailVendedor = "vendedor@pedidos.test";
    public const string EmailAdmin = "admin@pedidos.test";

    public static List<Usuario> UsuariosSemilla() => new()
    {
        Crear("Vendedor", "Uno", EmailVendedor, "VEN-0001", Roles.Vendedor, "+50255550102"),       // VendedorId
        Crear("Vendedor", "Dos", "vendedor2@pedidos.test", "VEN-0002", Roles.Vendedor, "+50255550103"), // OtroVendedorId
        Crear("Admin", "General", EmailAdmin, "ADM-0001", Roles.Admin, "+50255550101")             // AdminId
    };

    private static Usuario Crear(string nombre, string apellido, string email, string codigo, string rol, string telefono) => new()
    {
        Nombre = nombre,
        Apellido = apellido,
        Username = $"{nombre} {apellido}",
        Email = email,
        CodigoCorporativo = codigo,
        Telefono = telefono,
        PasswordHash = HashDePrueba,
        Rol = rol,
        CreadoEn = DateTime.UtcNow
    };

    /// <summary>Precios con IVA; costos promedio sin IVA.</summary>
    public static List<Producto> ProductosSemilla() => new()
    {
        new Producto { Codigo = "P001", Nombre = "Teclado", Precio = 150.00m, Stock = 10, CostoPromedio = 90.00m },
        new Producto { Codigo = "P002", Nombre = "Mouse", Precio = 75.50m, Stock = 5, CostoPromedio = 40.00m },
        new Producto { Codigo = "P003", Nombre = "Monitor", Precio = 1200.00m, Stock = 1, CostoPromedio = 800.00m }
    };

    public static List<CuentaContable> CuentasSemilla() => new (string Codigo, string Nombre)[]
        {
            ("1101", "Caja"),
            ("1102", "Bancos"),
            ("1103", "Inventario de mercadería"),
            ("1104", "IVA por cobrar (crédito fiscal)"),
            ("2101", "Proveedores"),
            ("2102", "IVA por pagar (débito fiscal)"),
            ("3101", "Capital social"),
            ("3102", "Resultados acumulados"),
            ("4101", "Ventas"),
            ("4102", "Otros ingresos"),
            ("5101", "Costo de ventas"),
            ("6101", "Sueldos y salarios"),
            ("6102", "Alquileres"),
            ("6103", "Energía eléctrica, agua y teléfono"),
            ("6104", "Faltantes y mermas de inventario"),
            ("6105", "Gastos varios"),
        }
        .Select(c => new CuentaContable { Codigo = c.Codigo, Nombre = c.Nombre, Tipo = TiposCuenta.DesdeCodigo(c.Codigo)! })
        .ToList();

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
