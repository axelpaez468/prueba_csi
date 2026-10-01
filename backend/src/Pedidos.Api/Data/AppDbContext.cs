using System.Text.Json;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.ChangeTracking;
using Pedidos.Api.Domain;

namespace Pedidos.Api.Data;

// El esquema real lo crea db/init/01-schema.sql; este mapeo debe mantenerse alineado con él.
public class AppDbContext : DbContext
{
    public AppDbContext(DbContextOptions<AppDbContext> options) : base(options) { }

    public DbSet<Usuario> Usuarios => Set<Usuario>();
    public DbSet<Producto> Productos => Set<Producto>();
    public DbSet<ProductoImagen> ProductoImagenes => Set<ProductoImagen>();
    public DbSet<Pedido> Pedidos => Set<Pedido>();
    public DbSet<PedidoDetalle> PedidoDetalles => Set<PedidoDetalle>();
    public DbSet<PedidoHistorial> PedidoHistorial => Set<PedidoHistorial>();
    public DbSet<EtapaPipeline> EtapasPipeline => Set<EtapaPipeline>();
    public DbSet<CodigoRespaldo> CodigosRespaldo => Set<CodigoRespaldo>();
    public DbSet<TokenRecuperacion> TokensRecuperacion => Set<TokenRecuperacion>();
    public DbSet<DispositivoConfiable> DispositivosConfiables => Set<DispositivoConfiable>();
    public DbSet<DispositivoConocido> DispositivosConocidos => Set<DispositivoConocido>();
    public DbSet<RegistroAcceso> BitacoraAccesos => Set<RegistroAcceso>();

    // ERP: ventas, inventario, compras y contabilidad.
    public DbSet<Cliente> Clientes => Set<Cliente>();
    public DbSet<Proveedor> Proveedores => Set<Proveedor>();
    public DbSet<MovimientoInventario> MovimientosInventario => Set<MovimientoInventario>();
    public DbSet<OrdenCompra> OrdenesCompra => Set<OrdenCompra>();
    public DbSet<OrdenCompraDetalle> OrdenCompraDetalles => Set<OrdenCompraDetalle>();
    public DbSet<CuentaContable> CuentasContables => Set<CuentaContable>();
    public DbSet<Partida> Partidas => Set<Partida>();
    public DbSet<PartidaDetalle> PartidaDetalles => Set<PartidaDetalle>();

    protected override void OnModelCreating(ModelBuilder model)
    {
        model.Entity<Usuario>(e =>
        {
            e.ToTable("Usuarios", t =>
            {
                t.HasCheckConstraint("CK_Usuarios_Rol", "Rol IN ('VENDEDOR','ADMIN','BODEGA','COMPRAS','CONTADOR')");
                t.HasCheckConstraint("CK_Usuarios_DosFactor", "DosFactor IN ('NINGUNO','TOTP')");
            });
            e.Property(u => u.Username).HasMaxLength(130).IsRequired();
            e.Property(u => u.Nombre).HasMaxLength(60).IsRequired();
            e.Property(u => u.Apellido).HasMaxLength(60).IsRequired();
            e.Property(u => u.CodigoCorporativo).HasMaxLength(20).IsRequired();
            e.Property(u => u.CreadoEn).HasConversion(v => v, v => DateTime.SpecifyKind(v, DateTimeKind.Utc));
            e.Property(u => u.Email).HasMaxLength(254).IsRequired();
            e.Property(u => u.PasswordHash).HasMaxLength(100).IsRequired();
            e.Property(u => u.Rol).HasMaxLength(20).IsRequired();
            e.Property(u => u.Telefono).HasMaxLength(20);
            e.Property(u => u.DosFactor).HasMaxLength(10).IsRequired();
            e.Property(u => u.TotpSecretoCifrado).HasMaxLength(200);
            e.Property(u => u.TotpPendienteCifrado).HasMaxLength(200);
            e.HasIndex(u => u.Email).IsUnique();
            e.Ignore(u => u.DosFactorObligatorio);
            e.HasIndex(u => u.CodigoCorporativo).IsUnique();
        });

        model.Entity<CodigoRespaldo>(e =>
        {
            e.ToTable("CodigosRespaldo");
            e.Property(c => c.CodigoHash).HasMaxLength(64).IsRequired();
            e.HasOne<Usuario>().WithMany().HasForeignKey(c => c.UsuarioId).OnDelete(DeleteBehavior.Cascade);
            e.HasIndex(c => c.UsuarioId);
        });

        model.Entity<TokenRecuperacion>(e =>
        {
            e.ToTable("TokensRecuperacion");
            e.Property(t => t.TokenHash).HasMaxLength(64).IsRequired();
            e.HasOne<Usuario>().WithMany().HasForeignKey(t => t.UsuarioId).OnDelete(DeleteBehavior.Cascade);
            e.HasIndex(t => t.TokenHash).IsUnique();
        });

        model.Entity<DispositivoConfiable>(e =>
        {
            e.ToTable("DispositivosConfiables");
            e.Property(d => d.TokenHash).HasMaxLength(64).IsRequired();
            e.HasOne<Usuario>().WithMany().HasForeignKey(d => d.UsuarioId).OnDelete(DeleteBehavior.Cascade);
            e.HasIndex(d => d.TokenHash).IsUnique();
        });

        model.Entity<DispositivoConocido>(e =>
        {
            e.ToTable("DispositivosConocidos");
            e.Property(d => d.Huella).HasMaxLength(64).IsRequired();
            e.HasOne<Usuario>().WithMany().HasForeignKey(d => d.UsuarioId).OnDelete(DeleteBehavior.Cascade);
            e.HasIndex(d => new { d.UsuarioId, d.Huella }).IsUnique();
        });

        model.Entity<RegistroAcceso>(e =>
        {
            e.ToTable("BitacoraAccesos");
            e.Property(r => r.Email).HasMaxLength(254).IsRequired();
            e.Property(r => r.Evento).HasMaxLength(40).IsRequired();
            e.Property(r => r.Ip).HasMaxLength(45);
            e.Property(r => r.UserAgent).HasMaxLength(300);
            e.Property(r => r.Detalle).HasMaxLength(300);
            e.Property(r => r.Fecha).HasConversion(v => v, v => DateTime.SpecifyKind(v, DateTimeKind.Utc));
            // Sin FK: se registran también intentos con correos que no existen.
            e.HasIndex(r => r.Fecha);
            e.HasIndex(r => r.UsuarioId);
        });

        model.Entity<Producto>(e =>
        {
            e.ToTable("Productos", t =>
            {
                t.HasCheckConstraint("CK_Productos_Stock", "Stock >= 0");
                t.HasCheckConstraint("CK_Productos_Precio", "Precio >= 0");
                t.HasCheckConstraint("CK_Productos_Costo", "CostoPromedio >= 0");
                t.HasCheckConstraint("CK_Productos_StockMinimo", "StockMinimo >= 0");
            });
            e.Property(p => p.Codigo).HasMaxLength(20).IsRequired();
            e.Property(p => p.Nombre).HasMaxLength(100).IsRequired();
            e.Property(p => p.Precio).HasPrecision(18, 2);
            e.Property(p => p.CostoPromedio).HasPrecision(18, 4);
            e.Property(p => p.Marca).HasMaxLength(60);
            e.Property(p => p.Categoria).HasMaxLength(60);
            e.Property(p => p.Descripcion).HasMaxLength(2000);
            // Lista de especificaciones como JSON: se lee y se escribe siempre completa con el producto.
            e.Property(p => p.Especificaciones)
                .HasMaxLength(4000)
                .HasConversion(
                    v => JsonSerializer.Serialize(v, (JsonSerializerOptions?)null),
                    v => string.IsNullOrEmpty(v)
                        ? new List<Especificacion>()
                        : JsonSerializer.Deserialize<List<Especificacion>>(v, (JsonSerializerOptions?)null) ?? new List<Especificacion>(),
                    new ValueComparer<List<Especificacion>>(
                        (a, b) => a!.SequenceEqual(b!),
                        v => v.Aggregate(0, (h, x) => HashCode.Combine(h, x.GetHashCode())),
                        v => v.ToList()));
            e.HasIndex(p => p.Codigo).IsUnique();
        });

        model.Entity<Pedido>(e =>
        {
            e.ToTable("Pedidos");
            e.Property(p => p.Total).HasPrecision(18, 2);
            // Se guarda en UTC; al leer se marca como UTC para que el JSON lleve la "Z".
            e.Property(p => p.Fecha).HasConversion(v => v, v => DateTime.SpecifyKind(v, DateTimeKind.Utc));
            e.HasOne<Usuario>().WithMany().HasForeignKey(p => p.UsuarioId).OnDelete(DeleteBehavior.Restrict);
            e.HasOne(p => p.Cliente).WithMany().HasForeignKey(p => p.ClienteId).OnDelete(DeleteBehavior.Restrict);
            e.HasMany(p => p.Detalles).WithOne().HasForeignKey(d => d.PedidoId);
            e.Property(p => p.FormaPago).HasMaxLength(15).IsRequired();
            e.Property(p => p.BaseImponible).HasPrecision(18, 2);
            e.Property(p => p.Iva).HasPrecision(18, 2);
            e.Property(p => p.Costo).HasPrecision(18, 2);
            e.Property(p => p.DireccionEntrega).HasMaxLength(200);
            e.Property(p => p.Departamento).HasMaxLength(40);
            e.Property(p => p.Municipio).HasMaxLength(60);
            e.Property(p => p.Estado).HasMaxLength(12).IsRequired();
            e.Property(p => p.EstadoDesde).HasConversion(v => v, v => DateTime.SpecifyKind(v, DateTimeKind.Utc));
            e.HasIndex(p => p.Estado);
            e.HasIndex(p => p.Departamento);
            e.HasIndex(p => p.UsuarioId);
            e.HasIndex(p => p.Fecha);
            e.HasIndex(p => p.ClienteId);
        });

        model.Entity<PedidoDetalle>(e =>
        {
            e.ToTable("PedidoDetalle", t => t.HasCheckConstraint("CK_PedidoDetalle_Cantidad", "Cantidad > 0"));
            e.HasKey(d => new { d.PedidoId, d.ProductoId });
            e.Property(d => d.PrecioUnitario).HasPrecision(18, 2);
            e.Property(d => d.Subtotal).HasPrecision(18, 2);
            e.Property(d => d.CostoUnitario).HasPrecision(18, 4);
            e.HasOne(d => d.Producto).WithMany().HasForeignKey(d => d.ProductoId).OnDelete(DeleteBehavior.Restrict);
        });

        ConfigurarErp(model);
    }

    private static void ConfigurarErp(ModelBuilder model)
    {
        model.Entity<PedidoHistorial>(e =>
        {
            e.ToTable("PedidoHistorial");
            e.Property(h => h.Estado).HasMaxLength(12).IsRequired();
            e.Property(h => h.Nota).HasMaxLength(200);
            e.Property(h => h.Fecha).HasConversion(v => v, v => DateTime.SpecifyKind(v, DateTimeKind.Utc));
            e.HasOne<Pedido>().WithMany().HasForeignKey(h => h.PedidoId).OnDelete(DeleteBehavior.Cascade);
            e.HasOne<Usuario>().WithMany().HasForeignKey(h => h.UsuarioId).OnDelete(DeleteBehavior.Restrict);
            e.HasIndex(h => new { h.PedidoId, h.Id });
        });

        model.Entity<EtapaPipeline>(e =>
        {
            e.ToTable("EtapasPipeline", t => t.HasCheckConstraint("CK_EtapasPipeline_Probabilidad",
                "CAST([Probabilidad] AS REAL) >= 0 AND CAST([Probabilidad] AS REAL) <= 100"));
            e.HasKey(x => x.Estado);
            e.Property(x => x.Estado).HasMaxLength(12);
            e.Property(x => x.Probabilidad).HasPrecision(5, 2);
            e.Property(x => x.ActualizadoPor).HasMaxLength(100);
            e.Property(x => x.ActualizadoEn).HasConversion(
                v => v, v => v == null ? null : DateTime.SpecifyKind(v.Value, DateTimeKind.Utc));
            // Mismos valores que siembra db/init/init.sql.
            e.HasData(EstadosVenta.Orden.Select(s => new EtapaPipeline { Estado = s, Probabilidad = EstadosVenta.ProbabilidadInicial[s] }));
        });

        model.Entity<ProductoImagen>(e =>
        {
            e.ToTable("ProductoImagenes");
            e.Property(i => i.ContentType).HasMaxLength(20).IsRequired();
            e.Property(i => i.Datos).IsRequired();
            e.Property(i => i.CreadoEn).HasConversion(v => v, v => DateTime.SpecifyKind(v, DateTimeKind.Utc));
            e.HasOne<Producto>().WithMany().HasForeignKey(i => i.ProductoId).OnDelete(DeleteBehavior.Cascade);
            e.HasIndex(i => new { i.ProductoId, i.Orden });
        });

        model.Entity<Cliente>(e =>
        {
            e.ToTable("Clientes");
            e.Property(c => c.Nit).HasMaxLength(15).IsRequired();
            e.Property(c => c.Nombre).HasMaxLength(150).IsRequired();
            e.Property(c => c.Direccion).HasMaxLength(200);
            e.Property(c => c.Telefono).HasMaxLength(20);
            e.Property(c => c.Email).HasMaxLength(254);
            e.Property(c => c.CreadoEn).HasConversion(v => v, v => DateTime.SpecifyKind(v, DateTimeKind.Utc));
            e.HasIndex(c => c.Nit).IsUnique();
        });

        model.Entity<Proveedor>(e =>
        {
            e.ToTable("Proveedores");
            e.Property(p => p.Nit).HasMaxLength(15).IsRequired();
            e.Property(p => p.Nombre).HasMaxLength(150).IsRequired();
            e.Property(p => p.Contacto).HasMaxLength(100);
            e.Property(p => p.Telefono).HasMaxLength(20);
            e.Property(p => p.Email).HasMaxLength(254);
            e.Property(p => p.Direccion).HasMaxLength(200);
            e.Property(p => p.CreadoEn).HasConversion(v => v, v => DateTime.SpecifyKind(v, DateTimeKind.Utc));
            e.HasIndex(p => p.Nit).IsUnique();
        });

        model.Entity<MovimientoInventario>(e =>
        {
            e.ToTable("MovimientosInventario", t => t.HasCheckConstraint("CK_Movimientos_Saldo", "Saldo >= 0"));
            e.Property(m => m.Tipo).HasMaxLength(20).IsRequired();
            e.Property(m => m.Referencia).HasMaxLength(120).IsRequired();
            e.Property(m => m.CostoUnitario).HasPrecision(18, 4);
            e.Property(m => m.CostoPromedio).HasPrecision(18, 4);
            e.Property(m => m.Fecha).HasConversion(v => v, v => DateTime.SpecifyKind(v, DateTimeKind.Utc));
            e.HasOne<Producto>().WithMany().HasForeignKey(m => m.ProductoId).OnDelete(DeleteBehavior.Restrict);
            e.HasOne<Usuario>().WithMany().HasForeignKey(m => m.UsuarioId).OnDelete(DeleteBehavior.Restrict);
            e.HasIndex(m => new { m.ProductoId, m.Id });
        });

        model.Entity<OrdenCompra>(e =>
        {
            e.ToTable("OrdenesCompra", t =>
                t.HasCheckConstraint("CK_OrdenesCompra_Estado", "Estado IN ('PENDIENTE','RECIBIDA','ANULADA')"));
            e.Property(o => o.Estado).HasMaxLength(10).IsRequired();
            e.Property(o => o.Subtotal).HasPrecision(18, 2);
            e.Property(o => o.Iva).HasPrecision(18, 2);
            e.Property(o => o.Total).HasPrecision(18, 2);
            e.Property(o => o.Observaciones).HasMaxLength(300);
            e.Property(o => o.FacturaProveedor).HasMaxLength(40);
            e.Property(o => o.Fecha).HasConversion(v => v, v => DateTime.SpecifyKind(v, DateTimeKind.Utc));
            e.Property(o => o.FechaRecepcion)
                .HasConversion(v => v, v => v == null ? null : DateTime.SpecifyKind(v.Value, DateTimeKind.Utc));
            e.HasOne(o => o.Proveedor).WithMany().HasForeignKey(o => o.ProveedorId).OnDelete(DeleteBehavior.Restrict);
            e.HasOne<Usuario>().WithMany().HasForeignKey(o => o.UsuarioId).OnDelete(DeleteBehavior.Restrict);
            e.HasOne<Usuario>().WithMany().HasForeignKey(o => o.RecibidaPorId).OnDelete(DeleteBehavior.Restrict);
            e.HasMany(o => o.Detalles).WithOne().HasForeignKey(d => d.OrdenCompraId);
            e.HasIndex(o => o.Estado);
        });

        model.Entity<OrdenCompraDetalle>(e =>
        {
            e.ToTable("OrdenCompraDetalle", t =>
            {
                t.HasCheckConstraint("CK_OrdenCompraDetalle_Cantidad", "Cantidad > 0");
                t.HasCheckConstraint("CK_OrdenCompraDetalle_Costo", "CostoUnitario > 0");
            });
            e.HasKey(d => new { d.OrdenCompraId, d.ProductoId });
            e.Property(d => d.CostoUnitario).HasPrecision(18, 2);
            e.Property(d => d.Subtotal).HasPrecision(18, 2);
            e.HasOne(d => d.Producto).WithMany().HasForeignKey(d => d.ProductoId).OnDelete(DeleteBehavior.Restrict);
        });

        model.Entity<CuentaContable>(e =>
        {
            e.ToTable("CuentasContables", t =>
                t.HasCheckConstraint("CK_Cuentas_Tipo", "Tipo IN ('ACTIVO','PASIVO','CAPITAL','INGRESO','COSTO','GASTO')"));
            e.Property(c => c.Codigo).HasMaxLength(10).IsRequired();
            e.Property(c => c.Nombre).HasMaxLength(100).IsRequired();
            e.Property(c => c.Tipo).HasMaxLength(10).IsRequired();
            e.HasIndex(c => c.Codigo).IsUnique();
        });

        model.Entity<Partida>(e =>
        {
            e.ToTable("Partidas");
            e.Property(p => p.Concepto).HasMaxLength(200).IsRequired();
            e.Property(p => p.Origen).HasMaxLength(10).IsRequired();
            e.Property(p => p.Total).HasPrecision(18, 2);
            e.Property(p => p.CreadoEn).HasConversion(v => v, v => DateTime.SpecifyKind(v, DateTimeKind.Utc));
            e.HasOne<Usuario>().WithMany().HasForeignKey(p => p.UsuarioId).OnDelete(DeleteBehavior.Restrict);
            e.HasMany(p => p.Detalles).WithOne().HasForeignKey(d => d.PartidaId);
            e.HasIndex(p => p.Fecha);
            e.HasIndex(p => new { p.Origen, p.ReferenciaId });
        });

        model.Entity<PartidaDetalle>(e =>
        {
            e.ToTable("PartidaDetalle", t =>
                // Cada línea va al debe o al haber, nunca a ambos ni con montos negativos.
                t.HasCheckConstraint("CK_PartidaDetalle_Montos",
                    // CAST: en SQLite (pruebas) los decimales se guardan como texto; en SQL Server no cambia nada.
                    "CAST(Debe AS REAL) >= 0 AND CAST(Haber AS REAL) >= 0 AND " +
                    "((CAST(Debe AS REAL) > 0 AND CAST(Haber AS REAL) = 0) OR (CAST(Haber AS REAL) > 0 AND CAST(Debe AS REAL) = 0))"));
            e.Property(d => d.Debe).HasPrecision(18, 2);
            e.Property(d => d.Haber).HasPrecision(18, 2);
            e.HasOne(d => d.Cuenta).WithMany().HasForeignKey(d => d.CuentaId).OnDelete(DeleteBehavior.Restrict);
            e.HasIndex(d => d.CuentaId);
        });
    }
}
