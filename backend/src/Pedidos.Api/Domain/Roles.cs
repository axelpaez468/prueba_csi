namespace Pedidos.Api.Domain;

/// <summary>
/// Roles del ERP (separación de funciones). ADMIN ve todos los módulos; solo VENDEDOR registra ventas.
/// Las combinaciones son listas para [Authorize(Roles = ...)], que acepta roles separados por coma.
/// </summary>
public static class Roles
{
    public const string Vendedor = "VENDEDOR";
    public const string Admin = "ADMIN";
    public const string Bodega = "BODEGA";
    public const string Compras = "COMPRAS";
    public const string Contador = "CONTADOR";

    public static readonly string[] Todos = { Vendedor, Admin, Bodega, Compras, Contador };

    /// <summary>Clientes: los atiende ventas.</summary>
    public const string GestionClientes = Vendedor + "," + Admin;

    /// <summary>Consulta de ventas (facturas): el vendedor ve solo las suyas.</summary>
    public const string ConsultaVentas = Vendedor + "," + Admin + "," + Contador;

    /// <summary>Productos, precios y ajustes de inventario.</summary>
    public const string GestionInventario = Bodega + "," + Admin;

    /// <summary>Existencias, costos y kardex (solo lectura).</summary>
    public const string ConsultaInventario = Bodega + "," + Admin + "," + Compras + "," + Contador;

    /// <summary>Proveedores y órdenes de compra.</summary>
    public const string GestionCompras = Compras + "," + Admin;

    /// <summary>Recepción de mercadería: la hace bodega (o compras).</summary>
    public const string RecepcionCompras = Bodega + "," + Compras + "," + Admin;

    public const string ConsultaCompras = Bodega + "," + Compras + "," + Admin + "," + Contador;

    public const string Contabilidad = Contador + "," + Admin;

    /// <summary>Panel de indicadores: todos menos el vendedor, que trabaja desde el catálogo.</summary>
    public const string Panel = Admin + "," + Bodega + "," + Compras + "," + Contador;
}
