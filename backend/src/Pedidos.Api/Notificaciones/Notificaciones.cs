using System.Threading.Channels;
using MailKit.Net.Smtp;
using MailKit.Security;
using Microsoft.Extensions.Options;
using MimeKit;

namespace Pedidos.Api.Notificaciones;

public class CorreoOptions
{
    public const string Section = "Correo";

    /// <summary>Servidor SMTP. En desarrollo/Docker: Mailpit (bandeja web gratuita, no envía correos reales).</summary>
    public string Host { get; set; } = "localhost";
    public int Puerto { get; set; } = 1025;
    public string Remitente { get; set; } = "no-responder@pedidos.local";
    public string? Usuario { get; set; }

    /// <summary>Solo por variable de entorno (Correo__Password). Para Gmail: una "contraseña de aplicación".</summary>
    public string? Password { get; set; }

    /// <summary>
    /// "None" (Mailpit), "StartTls" (puerto 587) o "SslOnConnect" (puerto 465, p. ej. Gmail).
    /// </summary>
    public string Tls { get; set; } = "None";

    public SecureSocketOptions ModoTls => Tls.ToLowerInvariant() switch
    {
        "starttls" => SecureSocketOptions.StartTls,
        "sslonconnect" or "ssl" => SecureSocketOptions.SslOnConnect,
        _ => SecureSocketOptions.None
    };
}

public class SmsOptions
{
    public const string Section = "Sms";

    /// <summary>
    /// "Simulado": los SMS se entregan en la bandeja de Mailpit (gratis, para pruebas).
    /// Para producción se implementaría otro <see cref="IEnviadorSms"/> (p. ej. Twilio) y se cambia este valor.
    /// </summary>
    public string Proveedor { get; set; } = "Simulado";

    /// <summary>
    /// Correo donde se entregan los SMS simulados. Vacío: una dirección ficticia por teléfono
    /// (sms-50255550101@sms.simulado), útil con Mailpit. Con un SMTP real (Gmail) debe ser un buzón existente.
    /// </summary>
    public string? DestinoSimulado { get; set; }
}

public record Mensaje(string Para, string Asunto, string Texto);

public interface IEnviadorCorreo
{
    void Encolar(string para, string asunto, string texto);
}

public interface IEnviadorSms
{
    void Encolar(string telefono, string texto);
}

/// <summary>
/// Cola en memoria: la petición HTTP solo encola y responde. Así el usuario no espera al servidor de correo,
/// un fallo de SMTP no rompe el login, y el tiempo de respuesta no revela si un correo existe.
/// </summary>
public class ColaNotificaciones : IEnviadorCorreo
{
    private readonly Channel<Mensaje> _canal = Channel.CreateBounded<Mensaje>(
        new BoundedChannelOptions(1000) { FullMode = BoundedChannelFullMode.DropOldest });

    public ChannelReader<Mensaje> Lector => _canal.Reader;

    public void Encolar(string para, string asunto, string texto) =>
        _canal.Writer.TryWrite(new Mensaje(para, asunto, texto));
}

/// <summary>SMS simulado: se entrega como correo a una dirección ficticia, visible en la bandeja de Mailpit.</summary>
public class SmsSimulado : IEnviadorSms
{
    private readonly IEnviadorCorreo _correo;
    private readonly string? _destino;

    public SmsSimulado(IEnviadorCorreo correo, IOptions<SmsOptions> opciones)
    {
        _correo = correo;
        _destino = string.IsNullOrWhiteSpace(opciones.Value.DestinoSimulado) ? null : opciones.Value.DestinoSimulado.Trim();
    }

    public void Encolar(string telefono, string texto)
    {
        var digitos = new string(telefono.Where(char.IsDigit).ToArray());
        _correo.Encolar(_destino ?? $"sms-{digitos}@sms.simulado", $"📱 SMS a {telefono}", texto);
    }
}

/// <summary>Envía por SMTP los mensajes encolados, con reintentos.</summary>
public class ProcesadorNotificaciones : BackgroundService
{
    private readonly ColaNotificaciones _cola;
    private readonly CorreoOptions _opciones;
    private readonly ILogger<ProcesadorNotificaciones> _logger;

    public ProcesadorNotificaciones(ColaNotificaciones cola, IOptions<CorreoOptions> opciones,
        ILogger<ProcesadorNotificaciones> logger)
    {
        _cola = cola;
        _opciones = opciones.Value;
        _logger = logger;
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        await foreach (var mensaje in _cola.Lector.ReadAllAsync(stoppingToken))
        {
            for (var intento = 1; intento <= 3; intento++)
            {
                try
                {
                    await EnviarAsync(mensaje, stoppingToken);
                    break;
                }
                catch (Exception ex) when (ex is not OperationCanceledException)
                {
                    // No se registra el contenido: puede incluir códigos o enlaces de recuperación.
                    _logger.LogWarning("Fallo al enviar notificación (intento {Intento}/3): {Error}", intento, ex.Message);
                    await Task.Delay(TimeSpan.FromSeconds(intento * 2), stoppingToken);
                }
            }
        }
    }

    private async Task EnviarAsync(Mensaje m, CancellationToken ct)
    {
        var correo = new MimeMessage();
        correo.From.Add(new MailboxAddress("Sistema de Pedidos", _opciones.Remitente));
        correo.To.Add(MailboxAddress.Parse(m.Para));
        correo.Subject = m.Asunto;
        correo.Body = new TextPart("plain") { Text = m.Texto };

        using var smtp = new SmtpClient { Timeout = 10_000 };
        await smtp.ConnectAsync(_opciones.Host, _opciones.Puerto, _opciones.ModoTls, ct);
        if (!string.IsNullOrEmpty(_opciones.Usuario))
            await smtp.AuthenticateAsync(_opciones.Usuario, _opciones.Password ?? string.Empty, ct);
        await smtp.SendAsync(correo, ct);
        await smtp.DisconnectAsync(true, ct);
    }
}
