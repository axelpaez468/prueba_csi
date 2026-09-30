namespace Pedidos.Api.Dtos;

/// <summary>Montos con IVA salvo que el nombre diga "sin IVA". Utilidad = ventas sin IVA − costo.</summary>
public record ResumenVentasResponse(
    int Facturas,
    int Unidades,
    decimal Total,
    decimal BaseImponible,
    decimal Iva,
    decimal Costo,
    decimal UtilidadBruta,
    // Margen sobre las ventas sin IVA (%).
    decimal Margen,
    decimal TicketPromedio);

public record VentaPorDiaResponse(DateOnly Fecha, int Facturas, decimal Total);

public record VentaPorProductoResponse(
    int ProductoId, string Codigo, string Nombre, string? Categoria, int Unidades, decimal Total, decimal VentasSinIva,
    decimal Costo, decimal Utilidad, decimal Margen, decimal Participacion);

public record VentaPorCategoriaResponse(string Categoria, int Unidades, decimal Total, decimal Utilidad, decimal Participacion);

public record VentaPorVendedorResponse(int UsuarioId, string Vendedor, int Facturas, decimal Total, decimal Utilidad, decimal Participacion);

public record VentaPorClienteResponse(int ClienteId, string Nit, string Cliente, int Facturas, decimal Total, decimal Participacion);

public record VentaPorFormaPagoResponse(string FormaPago, int Facturas, decimal Total, decimal Participacion);

public record ReporteVentasResponse(
    DateOnly Desde,
    DateOnly Hasta,
    ResumenVentasResponse Resumen,
    // Mismo resumen para el período anterior de igual duración (para comparar).
    ResumenVentasResponse PeriodoAnterior,
    List<VentaPorDiaResponse> PorDia,
    List<VentaPorProductoResponse> PorProducto,
    List<VentaPorCategoriaResponse> PorCategoria,
    List<VentaPorVendedorResponse> PorVendedor,
    List<VentaPorClienteResponse> PorCliente,
    List<VentaPorFormaPagoResponse> PorFormaPago);
