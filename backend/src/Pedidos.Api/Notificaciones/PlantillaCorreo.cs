using System.Text;
using Pedidos.Api.Services.Erp;

namespace Pedidos.Api.Notificaciones;

public enum TipoCorreo
{
    /// <summary>Bienvenida, enlaces y avisos generales.</summary>
    Informativo,

    /// <summary>Algo salió bien (cuenta activa, 2FA activado).</summary>
    Exito,

    /// <summary>Cambios de seguridad que el usuario debe revisar (contraseña, dispositivo nuevo).</summary>
    Seguridad
}

/// <summary>
/// Correo con el diseño del ERP. Se envía en HTML (con estilos en línea y tablas, que es lo que soportan Gmail
/// y Outlook) y también en texto plano para clientes que no muestran HTML. Todo el contenido variable se escapa:
/// un nombre como "&lt;a href=...&gt;" llega como texto y no como un enlace.
/// </summary>
public sealed record PlantillaCorreo(
    string Asunto,
    string Titulo,
    string Saludo,
    IReadOnlyList<string> Parrafos,
    TipoCorreo Tipo = TipoCorreo.Informativo,
    IReadOnlyList<(string Etiqueta, string Valor)>? Datos = null,
    string? TextoBoton = null,
    string? UrlBoton = null,
    string? NotaBoton = null,
    string? Aviso = null)
{
    /// <summary>Hora de Guatemala para mostrar en los correos (la BD guarda UTC).</summary>
    public static string Hora(DateTime utc) => $"{utc + Calendario.Desfase:dd/MM/yyyy HH:mm} (hora de Guatemala)";

    /// <summary>Escapa solo lo que puede romper el HTML (las tildes y la ñ se dejan tal cual, el correo va en UTF-8).</summary>
    private static string H(string texto) => texto
        .Replace("&", "&amp;").Replace("<", "&lt;").Replace(">", "&gt;").Replace("\"", "&quot;").Replace("'", "&#39;");

    private (string Color, string Fondo, string Icono, string Etiqueta) Estilo => Tipo switch
    {
        TipoCorreo.Exito => ("#0E9F6E", "#E7F6EF", "&#10003;", "Confirmación"),
        TipoCorreo.Seguridad => ("#B26A00", "#FFF3DC", "&#128274;", "Aviso de seguridad"),
        _ => ("#2450C8", "#E3EAFB", "&#9993;", "Notificación"),
    };

    public string Texto()
    {
        var sb = new StringBuilder();
        sb.AppendLine(Saludo).AppendLine();
        foreach (var p in Parrafos) sb.AppendLine(p).AppendLine();
        if (Datos is { Count: > 0 })
        {
            foreach (var (etiqueta, valor) in Datos) sb.AppendLine($"  {etiqueta}: {valor}");
            sb.AppendLine();
        }
        if (UrlBoton is not null)
        {
            sb.AppendLine($"{TextoBoton}:").AppendLine(UrlBoton);
            if (NotaBoton is not null) sb.AppendLine(NotaBoton);
            sb.AppendLine();
        }
        if (Aviso is not null) sb.AppendLine(Aviso).AppendLine();
        sb.AppendLine("—").AppendLine("Sistema de Pedidos · Mensaje automático, no respondas a este correo.");
        return sb.ToString();
    }

    public string Html()
    {
        var (color, fondo, icono, etiqueta) = Estilo;
        var sb = new StringBuilder();
        sb.Append($$"""
            <!DOCTYPE html>
            <html lang="es"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
            <title>{{H(Asunto)}}</title></head>
            <body style="margin:0;padding:0;background:#F1F4F9;font-family:Segoe UI,Roboto,Helvetica,Arial,sans-serif;color:#0F172A;">
            <div style="display:none;max-height:0;overflow:hidden;opacity:0;">{{H(Parrafos.FirstOrDefault() ?? Titulo)}}</div>
            <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#F1F4F9;padding:24px 12px;">
            <tr><td align="center">
            <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="max-width:600px;background:#FFFFFF;border-radius:16px;overflow:hidden;border:1px solid #E3E8EF;">
              <tr><td style="background:#0B1426;background-image:linear-gradient(135deg,#0B1426 0%,#16307F 60%,#2450C8 100%);padding:22px 32px;">
                <table role="presentation" cellpadding="0" cellspacing="0"><tr>
                  <td style="background:rgba(255,255,255,0.14);border-radius:10px;width:38px;height:38px;text-align:center;font-size:20px;color:#FFFFFF;">&#9638;</td>
                  <td style="padding-left:12px;color:#FFFFFF;font-size:20px;font-weight:700;letter-spacing:-0.3px;">Pedidos <span style="font-weight:400;color:#B9C8F5;">ERP</span></td>
                </tr></table>
              </td></tr>
              <tr><td style="height:4px;background:{{color}};font-size:0;line-height:0;">&nbsp;</td></tr>
              <tr><td style="padding:32px 32px 8px 32px;">
                <span style="display:inline-block;background:{{fondo}};color:{{color}};border-radius:99px;padding:4px 12px;font-size:12px;font-weight:700;letter-spacing:0.4px;">{{icono}} {{etiqueta.ToUpperInvariant()}}</span>
                <h1 style="margin:16px 0 8px 0;font-size:24px;line-height:1.25;font-weight:800;color:#0F172A;">{{H(Titulo)}}</h1>
                <p style="margin:0 0 16px 0;font-size:16px;line-height:1.6;">{{H(Saludo)}}</p>
            """);
        foreach (var p in Parrafos)
            sb.Append($"""<p style="margin:0 0 16px 0;font-size:15px;line-height:1.6;color:#334155;">{H(p)}</p>""");

        if (Datos is { Count: > 0 })
        {
            sb.Append("""<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="margin:8px 0 20px 0;border:1px solid #E3E8EF;border-radius:12px;border-collapse:separate;overflow:hidden;">""");
            foreach (var (i, (etiquetaDato, valor)) in Datos.Select((d, i) => (i, d)))
                sb.Append($"""
                    <tr style="background:{(i % 2 == 0 ? "#F8FAFD" : "#FFFFFF")};">
                      <td style="padding:10px 16px;font-size:13px;color:#64748B;width:40%;">{H(etiquetaDato)}</td>
                      <td style="padding:10px 16px;font-size:14px;font-weight:600;color:#0F172A;">{H(valor)}</td>
                    </tr>
                    """);
            sb.Append("</table>");
        }

        if (UrlBoton is not null)
        {
            sb.Append($$"""
                <table role="presentation" cellpadding="0" cellspacing="0" style="margin:8px 0 12px 0;"><tr>
                  <td style="border-radius:10px;background:{{color}};">
                    <a href="{{H(UrlBoton)}}" style="display:inline-block;padding:14px 28px;font-size:15px;font-weight:700;color:#FFFFFF;text-decoration:none;border-radius:10px;">{{H(TextoBoton ?? "Abrir")}}</a>
                  </td></tr></table>
                """);
            if (NotaBoton is not null)
                sb.Append($"""<p style="margin:0 0 8px 0;font-size:13px;color:#64748B;">{H(NotaBoton)}</p>""");
            sb.Append($"""
                <p style="margin:0 0 20px 0;font-size:12px;color:#94A3B8;line-height:1.5;">¿El botón no funciona? Copia este enlace en tu navegador:<br>
                <a href="{H(UrlBoton)}" style="color:#2450C8;word-break:break-all;">{H(UrlBoton)}</a></p>
                """);
        }

        if (Aviso is not null)
            sb.Append($"""
                <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="margin:4px 0 20px 0;"><tr>
                  <td style="background:#FFF7E6;border-left:4px solid #F59E0B;border-radius:8px;padding:12px 16px;font-size:13px;line-height:1.5;color:#7A4A00;">{H(Aviso)}</td>
                </tr></table>
                """);

        sb.Append("""
              </td></tr>
              <tr><td style="padding:20px 32px 28px 32px;border-top:1px solid #E3E8EF;font-size:12px;line-height:1.6;color:#94A3B8;">
                Este es un mensaje automático del <strong style="color:#64748B;">Sistema de Pedidos</strong>; no respondas a este correo.<br>
                Nunca te pediremos tu contraseña ni tus códigos de verificación por correo o por teléfono.
              </td></tr>
            </table>
            <p style="margin:16px 0 0 0;font-size:11px;color:#94A3B8;">Guatemala</p>
            </td></tr></table></body></html>
            """);
        return sb.ToString();
    }
}

public static class EnviadorCorreoExtensiones
{
    /// <summary>Encola el correo con diseño (HTML + texto plano).</summary>
    public static void Encolar(this IEnviadorCorreo enviador, string para, PlantillaCorreo plantilla) =>
        enviador.Encolar(para, plantilla.Asunto, plantilla.Texto(), plantilla.Html());
}
