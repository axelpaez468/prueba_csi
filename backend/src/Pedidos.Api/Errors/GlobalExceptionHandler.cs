using Microsoft.AspNetCore.Diagnostics;

namespace Pedidos.Api.Errors;

/// <summary>
/// Traduce excepciones a respuestas { "error": "..." }. Los errores inesperados se registran
/// en el log del servidor, pero al cliente nunca le llega el stack trace ni el mensaje de la BD.
/// </summary>
public class GlobalExceptionHandler : IExceptionHandler
{
    private readonly ILogger<GlobalExceptionHandler> _logger;

    public GlobalExceptionHandler(ILogger<GlobalExceptionHandler> logger) => _logger = logger;

    public async ValueTask<bool> TryHandleAsync(HttpContext context, Exception exception, CancellationToken ct)
    {
        var (status, mensaje) = exception switch
        {
            BusinessRuleException e => (StatusCodes.Status400BadRequest, e.Message),
            // Incluye 413 (cuerpo mayor al límite de Kestrel) y otros errores de protocolo.
            BadHttpRequestException e => (e.StatusCode, e.StatusCode == StatusCodes.Status413PayloadTooLarge
                ? "La solicitud es demasiado grande."
                : "La solicitud no es válida."),
            _ => (StatusCodes.Status500InternalServerError, "Ocurrió un error inesperado. Intente de nuevo más tarde.")
        };

        if (status == StatusCodes.Status500InternalServerError)
            _logger.LogError(exception, "Error no controlado en {Method} {Path}", context.Request.Method, context.Request.Path);

        context.Response.StatusCode = status;
        await context.Response.WriteAsJsonAsync(new ErrorResponse(mensaje), ct);
        return true;
    }
}
