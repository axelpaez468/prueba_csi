namespace Pedidos.Api.Dtos;

/// <summary>Producto del catálogo. Los primeros cinco campos son el contrato original; marca y categoría se agregaron después.</summary>
/// <param name="ImagenId">Foto principal (GET /api/productos/{id}/imagenes/{imagenId}); null si no tiene fotos.</param>
public record ProductoDto(
    int Id, string Codigo, string Nombre, decimal Precio, int Stock, string? Marca = null, string? Categoria = null, int? ImagenId = null);

public record EspecificacionDto(string? Nombre, string? Valor);

/// <summary>Ficha completa del producto para la pantalla de detalle.</summary>
public record ProductoDetalleDto(
    int Id,
    string Codigo,
    string Nombre,
    decimal Precio,
    int Stock,
    string? Marca,
    string? Categoria,
    string? Descripcion,
    int GarantiaMeses,
    List<EspecificacionDto> Especificaciones,
    List<int> Imagenes);
