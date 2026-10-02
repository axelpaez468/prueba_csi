namespace Pedidos.Api.Dtos;

public record CuentaResponse(int Id, string Codigo, string Nombre, string Tipo, bool Activa, bool EsSistema, decimal Saldo);

/// <param name="Codigo">4 a 10 dígitos; el primero define el tipo (1 activo ... 6 gasto). No se puede cambiar.</param>
public record GuardarCuentaRequest(string? Codigo, string? Nombre, bool? Activa);

public record LineaPartidaRequest(int CuentaId, decimal Debe, decimal Haber);

/// <param name="Fecha">Fecha contable; si no se envía, hoy (hora de Guatemala).</param>
public record CrearPartidaRequest(DateOnly? Fecha, string? Concepto, List<LineaPartidaRequest>? Lineas);

public record LineaPartidaResponse(int CuentaId, string Codigo, string Cuenta, decimal Debe, decimal Haber);

public record PartidaResponse(
    int Numero,
    DateOnly Fecha,
    string Concepto,
    string Origen,
    long? ReferenciaId,
    decimal Total,
    DateTime CreadoEn,
    List<LineaPartidaResponse> Lineas);

public record MovimientoMayorResponse(DateOnly Fecha, int Partida, string Concepto, decimal Debe, decimal Haber, decimal Saldo);

/// <summary>El saldo se expresa según la naturaleza de la cuenta (positivo = saldo normal).</summary>
public record LibroMayorResponse(
    CuentaResponse Cuenta,
    DateOnly Desde,
    DateOnly Hasta,
    decimal SaldoInicial,
    decimal TotalDebe,
    decimal TotalHaber,
    decimal SaldoFinal,
    List<MovimientoMayorResponse> Movimientos);

public record FilaBalanceComprobacion(
    string Codigo, string Cuenta, string Tipo, decimal Debe, decimal Haber, decimal SaldoDeudor, decimal SaldoAcreedor);

public record BalanceComprobacionResponse(
    DateOnly Desde,
    DateOnly Hasta,
    List<FilaBalanceComprobacion> Filas,
    decimal TotalDebe,
    decimal TotalHaber,
    decimal TotalSaldoDeudor,
    decimal TotalSaldoAcreedor,
    bool Cuadra);

public record RenglonReporte(string Codigo, string Cuenta, decimal Monto);

public record EstadoResultadosResponse(
    DateOnly Desde,
    DateOnly Hasta,
    List<RenglonReporte> Ingresos,
    decimal TotalIngresos,
    List<RenglonReporte> Costos,
    decimal TotalCostos,
    decimal UtilidadBruta,
    List<RenglonReporte> Gastos,
    decimal TotalGastos,
    decimal UtilidadNeta);

public record BalanceGeneralResponse(
    DateOnly Al,
    List<RenglonReporte> Activos,
    decimal TotalActivos,
    List<RenglonReporte> Pasivos,
    decimal TotalPasivos,
    List<RenglonReporte> Capital,
    decimal ResultadoDelEjercicio,
    decimal TotalCapital,
    decimal TotalPasivoYCapital,
    bool Cuadra);
