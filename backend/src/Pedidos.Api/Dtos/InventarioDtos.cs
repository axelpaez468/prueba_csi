namespace Pedidos.Api.Dtos;

public record ProductoInventarioResponse(
    int Id,
    string Codigo,
    string Nombre,
    decimal Precio,
    int Stock,
    int StockMinimo,
    decimal CostoPromedio,
    decimal ValorInventario,
    bool Activo,
    bool BajoMinimo,
    // Margen bruto sobre el precio sin IVA (%); null si el producto aún no tiene costo.
    decimal? Margen,
    string? Marca,
    string? Categoria,
    string? Descripcion,
    int GarantiaMeses,
    List<EspecificacionDto> Especificaciones,
    // Ids de las fotos, en orden; la primera es la principal.
    List<int> Imagenes);

/// <param name="Precio">Precio de venta con IVA incluido.</param>
/// <param name="Codigo">Solo al crear; después no cambia (lo usan facturas y kardex).</param>
/// <param name="Descripcion">Descripción comercial; admite párrafos (hasta 2000 caracteres).</param>
/// <param name="Especificaciones">Hasta 20 pares nombre/valor, p. ej. "Conexión" / "USB-C".</param>
public record GuardarProductoRequest(
    string? Codigo,
    string? Nombre,
    decimal Precio,
    int StockMinimo,
    bool? Activo,
    string? Marca = null,
    string? Categoria = null,
    string? Descripcion = null,
    int GarantiaMeses = 0,
    List<EspecificacionDto>? Especificaciones = null);

/// <param name="Tipo">ENTRADA o SALIDA.</param>
/// <param name="CostoUnitario">Solo entradas, sin IVA. Si se omite se usa el costo promedio actual.</param>
public record AjusteInventarioRequest(int ProductoId, string? Tipo, int Cantidad, decimal? CostoUnitario, string? Motivo);

public record MovimientoResponse(
    long Id,
    DateTime Fecha,
    string Tipo,
    int Cantidad,
    decimal CostoUnitario,
    int Saldo,
    decimal CostoPromedio,
    string Referencia,
    string? Usuario);

public record KardexResponse(ProductoInventarioResponse Producto, List<MovimientoResponse> Movimientos);
