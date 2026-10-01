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

/// <summary>Ventas por departamento de entrega, con el producto más vendido ahí (para el mapa).</summary>
public record VentaPorDepartamentoResponse(
    string Departamento, string? Iso, int Facturas, int Unidades, decimal Total, decimal Participacion,
    string? ProductoTop, int UnidadesProductoTop);

public record VentaPorEstadoResponse(string Estado, string Nombre, int Facturas, decimal Total);

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
    List<VentaPorFormaPagoResponse> PorFormaPago,
    List<VentaPorDepartamentoResponse> PorDepartamento,
    List<VentaPorEstadoResponse> PorEstado);

/// <summary>Una etapa del pipeline en el pronóstico: ventas en la etapa y su valor ponderado (total × probabilidad).</summary>
public record EtapaPronosticoResponse(string Estado, string Nombre, decimal Probabilidad, int Facturas, decimal Total, decimal Ponderado);

/// <summary>Un tramo de la tendencia (día, semana o mes, según el largo del rango).</summary>
public record PronosticoPeriodoResponse(DateOnly Desde, DateOnly Hasta, decimal Cerrado, decimal Abierto, decimal Ponderado);

public record PronosticoVendedorResponse(
    int UsuarioId, string Vendedor, int Facturas, decimal Cerrado, decimal Abierto, decimal Ponderado, decimal Pronostico);

/// <summary>
/// Pronóstico (forecast) de las ventas del rango: lo cerrado (entregado y cobrado) más lo que se espera cerrar de las
/// ventas abiertas, que es el total de cada etapa por su probabilidad de cierre.
/// </summary>
public record PronosticoResponse(
    DateOnly Desde,
    DateOnly Hasta,
    // DIA, SEMANA o MES: cómo se agrupa la tendencia.
    string Agrupacion,
    int FacturasCerradas,
    decimal Cerrado,
    int FacturasAbiertas,
    decimal Abierto,
    decimal PonderadoAbierto,
    // Cerrado + ponderado de las abiertas.
    decimal Pronostico,
    // Probabilidad media de las abiertas (ponderado / abierto, %).
    decimal ProbabilidadAbiertas,
    // Qué parte del pronóstico ya está cerrada (%).
    decimal AvanceCierre,
    List<EtapaPronosticoResponse> Etapas,
    List<PronosticoPeriodoResponse> Tendencia,
    List<PronosticoVendedorResponse> PorVendedor,
    DateTime? ProbabilidadesActualizadasEn,
    string? ProbabilidadesActualizadasPor);

public record ProbabilidadEtapaRequest(string Estado, decimal Probabilidad);

public record ActualizarProbabilidadesRequest(List<ProbabilidadEtapaRequest> Etapas);
