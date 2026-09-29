namespace Pedidos.Api.Dtos;

public record ProductoDto(int Id, string Codigo, string Nombre, decimal Precio, int Stock);
