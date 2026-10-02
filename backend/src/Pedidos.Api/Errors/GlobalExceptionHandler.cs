using Microsoft.AspNetCore.Diagnostics;
using Microsoft.Data.SqlClient;
using Microsoft.EntityFrameworkCore;

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
            // Dos personas guardan lo mismo a la vez (mismo NIT, código o correo): las validaciones de ambas pasaron,
            // pero el índice único de la BD solo deja entrar a una. La otra recibe un mensaje claro, no un 500.
            DbUpdateException { InnerException: SqlException { Number: 2601 or 2627 } } =>
                (StatusCodes.Status409Conflict, "Ya existe un registro con esos datos (alguien lo guardó al mismo tiempo). Revisa la lista."),
            // SQL Server eligió esta operación como víctima de un bloqueo mutuo: reintentarla funciona.
            DbUpdateException { InnerException: SqlException { Number: 1205 } } or SqlException { Number: 1205 } =>
                (StatusCodes.Status409Conflict, "La operación coincidió con otra al mismo tiempo. Intenta de nuevo."),
            NoEncontradoException e => (StatusCodes.Status404NotFound, e.Message),
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
