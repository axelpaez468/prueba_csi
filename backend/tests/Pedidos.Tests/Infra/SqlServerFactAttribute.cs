namespace Pedidos.Tests.Infra;

/// <summary>
/// Prueba que necesita un SQL Server real. Se omite si no está definida la variable
/// PEDIDOS_TEST_SQLSERVER con una cadena de conexión (usuario con permiso de crear bases).
/// </summary>
public sealed class SqlServerFactAttribute : FactAttribute
{
    public const string Variable = "PEDIDOS_TEST_SQLSERVER";

    public static string? ConnectionString => Environment.GetEnvironmentVariable(Variable);

    public SqlServerFactAttribute()
    {
        if (string.IsNullOrWhiteSpace(ConnectionString))
            Skip = $"Defina {Variable} para ejecutar pruebas contra SQL Server.";
    }
}
