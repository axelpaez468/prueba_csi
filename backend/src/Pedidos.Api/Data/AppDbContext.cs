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
    public DbSet<CodigoRespaldo> CodigosRespaldo => Set<CodigoRespaldo>();
    public DbSet<TokenRecuperacion> TokensRecuperacion => Set<TokenRecuperacion>();
    public DbSet<DispositivoConfiable> DispositivosConfiables => Set<DispositivoConfiable>();
    public DbSet<DispositivoConocido> DispositivosConocidos => Set<DispositivoConocido>();
    public DbSet<RegistroAcceso> BitacoraAccesos => Set<RegistroAcceso>();

    protected override void OnModelCreating(ModelBuilder model)
    {
        model.Entity<Usuario>(e =>
        {
            e.ToTable("Usuarios", t =>
            {
                t.HasCheckConstraint("CK_Usuarios_Rol", "Rol IN ('VENDEDOR','ADMIN')");
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
