namespace Pedidos.Api.Security;

/// <summary>
/// Topes de tamaño de la entrada. Evitan que un cliente consuma CPU o memoria con datos desproporcionados
/// (p. ej. un pedido con miles de líneas o una contraseña de megas que BCrypt tendría que procesar).
/// </summary>
public static class InputLimits
{
    public const int UsernameMax = 50;
    public const int PasswordMax = 128;
    public const int LineasPorPedidoMax = 50;
    public const int CantidadPorLineaMax = 1000;

    /// <summary>Tamaño máximo del cuerpo de cualquier petición (bytes).</summary>
    public const long CuerpoMaxBytes = 32 * 1024;
}
