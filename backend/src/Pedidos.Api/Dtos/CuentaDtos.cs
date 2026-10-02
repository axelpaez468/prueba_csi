namespace Pedidos.Api.Dtos;

public record EstadoSeguridadResponse(
    string Email,
    string Metodo,
    int CodigosRespaldoRestantes,
    bool DosFactorObligatorio);

public record CambiarPasswordRequest(string? Actual, string? Nueva);

public record IniciarTotpResponse(string Secreto, string Uri);

public record ConfirmarCodigoRequest(string? Codigo);

public record ConfirmarPasswordRequest(string? Password);

/// <summary>Se muestran una sola vez: el servidor solo guarda su huella.</summary>
public record CodigosRespaldoResponse(List<string> CodigosRespaldo);

public record RegistroAccesoResponse(
    DateTime Fecha,
    string Email,
    string Evento,
    bool Exito,
    string? Ip,
    string? Dispositivo,
    string? Detalle);
