using Microsoft.EntityFrameworkCore;
using Pedidos.Api.Domain;

namespace Pedidos.Api.Data;

// El esquema real lo crea db/init/01-schema.sql; este mapeo debe mantenerse alineado con él.
public class AppDbContext : DbContext
{
    public AppDbContext(DbContextOptions<AppDbContext> options) : base(options) { }

    public DbSet<Usuario> Usuarios => Set<Usuario>();
    public DbSet<Producto> Productos => Set<Producto>();
    public DbSet<Pedido> Pedidos => Set<Pedido>();
    public DbSet<PedidoDetalle> PedidoDetalles => Set<PedidoDetalle>();

    protected override void OnModelCreating(ModelBuilder model)
    {
        model.Entity<Usuario>(e =>
        {
            e.ToTable("Usuarios", t => t.HasCheckConstraint("CK_Usuarios_Rol", "Rol IN ('VENDEDOR','ADMIN')"));
            e.Property(u => u.Username).HasMaxLength(50).IsRequired();
            e.Property(u => u.PasswordHash).HasMaxLength(100).IsRequired();
            e.Property(u => u.Rol).HasMaxLength(20).IsRequired();
            e.HasIndex(u => u.Username).IsUnique();
        });

        model.Entity<Producto>(e =>
        {
            e.ToTable("Productos", t =>
            {
                t.HasCheckConstraint("CK_Productos_Stock", "Stock >= 0");
                t.HasCheckConstraint("CK_Productos_Precio", "Precio >= 0");
            });
            e.Property(p => p.Codigo).HasMaxLength(20).IsRequired();
            e.Property(p => p.Nombre).HasMaxLength(100).IsRequired();
            e.Property(p => p.Precio).HasPrecision(18, 2);
            e.HasIndex(p => p.Codigo).IsUnique();
        });

        model.Entity<Pedido>(e =>
        {
            e.ToTable("Pedidos");
            e.Property(p => p.Total).HasPrecision(18, 2);
            // Se guarda en UTC; al leer se marca como UTC para que el JSON lleve la "Z".
            e.Property(p => p.Fecha).HasConversion(v => v, v => DateTime.SpecifyKind(v, DateTimeKind.Utc));
            e.HasOne<Usuario>().WithMany().HasForeignKey(p => p.UsuarioId).OnDelete(DeleteBehavior.Restrict);
            e.HasMany(p => p.Detalles).WithOne().HasForeignKey(d => d.PedidoId);
            e.HasIndex(p => p.UsuarioId);
        });

        model.Entity<PedidoDetalle>(e =>
        {
            e.ToTable("PedidoDetalle", t => t.HasCheckConstraint("CK_PedidoDetalle_Cantidad", "Cantidad > 0"));
            e.HasKey(d => new { d.PedidoId, d.ProductoId });
            e.Property(d => d.PrecioUnitario).HasPrecision(18, 2);
            e.Property(d => d.Subtotal).HasPrecision(18, 2);
            e.HasOne(d => d.Producto).WithMany().HasForeignKey(d => d.ProductoId).OnDelete(DeleteBehavior.Restrict);
        });
    }
}
