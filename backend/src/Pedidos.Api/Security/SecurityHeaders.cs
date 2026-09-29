namespace Pedidos.Api.Security;

public static class SecurityHeaders
{
    /// <summary>
    /// Cabeceras defensivas para una API JSON: el navegador no debe interpretar las respuestas como HTML,
    /// incrustarlas en iframes ni guardarlas en caché (contienen datos de pedidos y tokens).
    /// </summary>
    public static IApplicationBuilder UseSecurityHeaders(this IApplicationBuilder app) =>
        app.Use(async (context, next) =>
        {
            var h = context.Response.Headers;
            h.XContentTypeOptions = "nosniff";
            h.XFrameOptions = "DENY";
            h["Referrer-Policy"] = "no-referrer";
            h["Permissions-Policy"] = "camera=(), microphone=(), geolocation=()";

            // Swagger UI (solo en desarrollo) necesita cargar scripts y estilos; el resto de la API no sirve HTML.
            if (!context.Request.Path.StartsWithSegments("/swagger"))
            {
                h.ContentSecurityPolicy = "default-src 'none'; frame-ancestors 'none'";
                h.CacheControl = "no-store";
            }

            await next();
        });
}
