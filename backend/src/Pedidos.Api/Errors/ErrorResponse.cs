namespace Pedidos.Api.Errors;

/// <summary>Formato único de error de la API: { "error": "..." }.</summary>
public record ErrorResponse(string Error);
