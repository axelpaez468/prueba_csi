using System.Text.RegularExpressions;
using Pedidos.Api.Errors;

namespace Pedidos.Api.Services.Erp;

/// <summary>NIT de Guatemala: número base más un dígito verificador (módulo 11; el 10 se escribe "K").</summary>
public static partial class Nit
{
    [GeneratedRegex(@"^\d{1,12}[0-9K]$")]
    private static partial Regex Formato();

    /// <summary>Quita guiones y espacios y pasa a mayúsculas: "1234567-9" → "12345679".</summary>
    public static string Normalizar(string? nit) =>
        new string((nit ?? "").Where(c => !char.IsWhiteSpace(c) && c != '-').ToArray()).ToUpperInvariant();

    public static bool EsValido(string nit)
    {
        if (!Formato().IsMatch(nit)) return false;
        var cuerpo = nit[..^1];
        var suma = 0;
        for (var i = 0; i < cuerpo.Length; i++)
            suma += (cuerpo[i] - '0') * (cuerpo.Length + 1 - i);
        var digito = (11 - suma % 11) % 11;
        return nit[^1] == (digito == 10 ? 'K' : (char)('0' + digito));
    }

    /// <summary>Para mostrar: "12345679" → "1234567-9".</summary>
    public static string Formatear(string nit) => nit.Length < 2 || !char.IsDigit(nit[0]) ? nit : $"{nit[..^1]}-{nit[^1]}";
}

/// <summary>
/// Fechas del negocio en hora de Guatemala (UTC-6, sin horario de verano). Las marcas de tiempo se guardan en
/// UTC; las fechas contables y los filtros "desde/hasta" son días locales.
/// </summary>
public static class Calendario
{
    public static readonly TimeSpan Desfase = TimeSpan.FromHours(-6);

    public static DateOnly FechaLocal(DateTime utc) => DateOnly.FromDateTime(utc + Desfase);

    public static DateOnly Hoy(TimeProvider reloj) => FechaLocal(reloj.GetUtcNow().UtcDateTime);

    /// <summary>Instante UTC en que empieza el día local.</summary>
    public static DateTime InicioUtc(DateOnly dia) => DateTime.SpecifyKind(dia.ToDateTime(TimeOnly.MinValue) - Desfase, DateTimeKind.Utc);

    /// <summary>Rango [inicio, fin) en UTC para filtrar marcas de tiempo por días locales (ambos incluidos).</summary>
    public static (DateTime Desde, DateTime Hasta) RangoUtc(DateOnly desde, DateOnly hasta)
    {
        if (hasta < desde)
            throw new BusinessRuleException("La fecha final no puede ser anterior a la inicial.");
        if (hasta.DayNumber - desde.DayNumber > 366)
            throw new BusinessRuleException("El rango de fechas no puede ser mayor a un año.");
        return (InicioUtc(desde), InicioUtc(hasta.AddDays(1)));
    }
}

public static class Montos
{
    public const decimal Maximo = 100_000_000m;

    /// <summary>Redondeo comercial a centavos (0.005 sube).</summary>
    public static decimal Redondear(decimal valor) => Math.Round(valor, 2, MidpointRounding.AwayFromZero);

    public static bool TieneCentavosValidos(decimal valor) => valor == Math.Round(valor, 2);

    /// <summary>Precio con IVA incluido → base imponible e IVA (la suma siempre da el total exacto).</summary>
    public static (decimal Base, decimal Iva) SepararIva(decimal totalConIva, decimal tasa)
    {
        var baseImponible = Redondear(totalConIva / (1 + tasa));
        return (baseImponible, totalConIva - baseImponible);
    }
}

/// <summary>Validaciones de datos de contacto compartidas por clientes y proveedores.</summary>
public static partial class Contacto
{
    [GeneratedRegex(@"^[^@\s]+@[^@\s]+\.[^@\s]{2,}$")]
    private static partial Regex RegexEmail();

    /// <summary>Quita espacios de más y caracteres de control; null si queda vacío.</summary>
    public static string? Limpiar(string? s)
    {
        var limpio = string.Join(' ', new string((s ?? "").Where(c => !char.IsControl(c)).ToArray())
            .Split(' ', StringSplitOptions.RemoveEmptyEntries));
        return limpio.Length == 0 ? null : limpio;
    }

    public static string Requerido(string? valor, int min, int max, string campo)
    {
        var v = Limpiar(valor);
        if (v is null || v.Length < min || v.Length > max)
            throw new BusinessRuleException($"{campo} es obligatorio ({min} a {max} caracteres).");
        return v;
    }

    public static string? Opcional(string? valor, int max, string campo)
    {
        var v = Limpiar(valor);
        if (v is not null && v.Length > max)
            throw new BusinessRuleException($"{campo} admite como máximo {max} caracteres.");
        return v;
    }

    public static string? Email(string? email)
    {
        var e = Limpiar(email)?.ToLowerInvariant();
        if (e is not null && (e.Length > 254 || !RegexEmail().IsMatch(e)))
            throw new BusinessRuleException("El correo electrónico no es válido.");
        return e;
    }

    /// <summary>Opcional; si viene, 8 dígitos de Guatemala (se guarda como +502XXXXXXXX).</summary>
    public static string? Telefono(string? telefono)
    {
        if (Limpiar(telefono) is null) return null;
        return Usuarios.UsuarioService.NormalizarTelefono(telefono)
               ?? throw new BusinessRuleException("El teléfono debe tener 8 dígitos de Guatemala, por ejemplo 2222 0101.");
    }
}
