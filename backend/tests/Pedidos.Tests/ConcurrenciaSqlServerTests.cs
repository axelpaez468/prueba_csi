using Microsoft.Data.SqlClient;
using Microsoft.EntityFrameworkCore;
using Pedidos.Api.Data;
using Pedidos.Api.Dtos;
using Pedidos.Api.Errors;
using Pedidos.Api.Services;
using Pedidos.Tests.Infra;

namespace Pedidos.Tests;

/// <summary>
/// Regla 2 bajo concurrencia real: muchos vendedores intentan comprar a la vez la última unidad.
/// Se ejecuta contra SQL Server porque SQLite serializa las escrituras y no reproduce el escenario.
/// </summary>
public class ConcurrenciaSqlServerTests
{
    private const int ProductoUltimaUnidad = 3;

    [SqlServerFact]
    public async Task PedidosSimultaneosPorLaUltimaUnidad_SoloUnoSeConfirma()
    {
        var builder = new SqlConnectionStringBuilder(SqlServerFactAttribute.ConnectionString)
        {
            InitialCatalog = $"PedidosTest_{Guid.NewGuid():N}"
        };
        var options = new DbContextOptionsBuilder<AppDbContext>().UseSqlServer(builder.ConnectionString).Options;

        await using (var db = new AppDbContext(options))
        {
            await db.Database.EnsureCreatedAsync();
            TestDb.Sembrar(db);
        }

        try
        {
            const int intentos = 20;
            using var largada = new ManualResetEventSlim(false);

            var tareas = Enumerable.Range(0, intentos).Select(_ => Task.Run(async () =>
            {
                largada.Wait();
                await using var db = new AppDbContext(options);
                try
                {
                    await TestDb.Ventas(db).CrearAsync(
                        TestDb.VendedorId, new CrearPedidoRequest(new() { new LineaPedidoRequest(ProductoUltimaUnidad, 1) }));
                    return true;
                }
                catch (BusinessRuleException)
                {
                    return false;
                }
            })).ToList();

            largada.Set();
            var resultados = await Task.WhenAll(tareas);

            Assert.Equal(1, resultados.Count(ok => ok));
            await using var verificacion = new AppDbContext(options);
            Assert.Equal(0, (await verificacion.Productos.SingleAsync(p => p.Id == ProductoUltimaUnidad)).Stock);
            Assert.Equal(1, await verificacion.Pedidos.CountAsync());
        }
        finally
        {
            await using var db = new AppDbContext(options);
            await db.Database.EnsureDeletedAsync();
        }
    }
}
