using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Pedidos.Api.Domain;
using Pedidos.Api.Dtos;
using Pedidos.Api.Errors;
using Pedidos.Api.Security;
using Pedidos.Api.Services.Erp;

namespace Pedidos.Api.Controllers;

/// <summary>Rango por defecto de los reportes: el mes en curso (hora de Guatemala).</summary>
internal static class RangoPorDefecto
{
    public static (DateOnly Desde, DateOnly Hasta) Resolver(DateOnly? desde, DateOnly? hasta, TimeProvider time)
    {
        var hoy = Calendario.Hoy(time);
        var fin = hasta ?? hoy;
        return (desde ?? new DateOnly(fin.Year, fin.Month, 1), fin);
    }
}

[ApiController]
[Route("api/clientes")]
[Authorize(Roles = Roles.GestionClientes)]
public class ClientesController : ControllerBase
{
    private readonly TercerosService _terceros;

    public ClientesController(TercerosService terceros) => _terceros = terceros;

    [HttpGet]
    public Task<List<ClienteResponse>> Listar([FromQuery] string? buscar, [FromQuery] bool inactivos, CancellationToken ct) =>
        _terceros.ListarClientesAsync(buscar, inactivos, ct);

    [HttpPost]
    [ProducesResponseType<ClienteResponse>(StatusCodes.Status201Created)]
    [ProducesResponseType<ErrorResponse>(StatusCodes.Status400BadRequest)]
    public async Task<IActionResult> Crear(GuardarClienteRequest request, CancellationToken ct) =>
        StatusCode(StatusCodes.Status201Created, await _terceros.CrearClienteAsync(request, ct));

    [HttpPut("{id:int}")]
    public Task<ClienteResponse> Editar(int id, GuardarClienteRequest request, CancellationToken ct) =>
        _terceros.EditarClienteAsync(id, request, ct);
}

[ApiController]
[Route("api/inventario")]
[Authorize(Roles = Roles.ConsultaInventario)]
public class InventarioController : ControllerBase
{
    private readonly InventarioService _inventario;

    public InventarioController(InventarioService inventario) => _inventario = inventario;

    [HttpGet("productos")]
    public Task<List<ProductoInventarioResponse>> Listar([FromQuery] string? buscar, [FromQuery] bool bajoMinimo,
        CancellationToken ct) => _inventario.ListarAsync(buscar, bajoMinimo, ct);

    [HttpPost("productos")]
    [Authorize(Roles = Roles.GestionInventario)]
    [ProducesResponseType<ProductoInventarioResponse>(StatusCodes.Status201Created)]
    public async Task<IActionResult> Crear(GuardarProductoRequest request, CancellationToken ct) =>
        StatusCode(StatusCodes.Status201Created, await _inventario.CrearAsync(request, ct));

    [HttpPut("productos/{id:int}")]
    [Authorize(Roles = Roles.GestionInventario)]
    public Task<ProductoInventarioResponse> Editar(int id, GuardarProductoRequest request, CancellationToken ct) =>
        _inventario.EditarAsync(id, request, ct);

    /// <summary>Solo productos sin ventas, compras ni movimientos; si no, hay que desactivarlo.</summary>
    [HttpDelete("productos/{id:int}")]
    [Authorize(Roles = Roles.GestionInventario)]
    [ProducesResponseType(StatusCodes.Status204NoContent)]
    [ProducesResponseType<ErrorResponse>(StatusCodes.Status400BadRequest)]
    public async Task<IActionResult> Eliminar(int id, CancellationToken ct)
    {
        await _inventario.EliminarAsync(id, ct);
        return NoContent();
    }

    /// <summary>Sube una foto (campo "archivo", JPG/PNG/WebP, hasta 2 MB; máximo 5 por producto). Devuelve los ids en orden.</summary>
    [HttpPost("productos/{id:int}/imagenes")]
    [Authorize(Roles = Roles.GestionInventario)]
    [RequestSizeLimit(ProductoImagen.TamanoMaximo + 64 * 1024)]
    [RequestFormLimits(MultipartBodyLengthLimit = ProductoImagen.TamanoMaximo + 64 * 1024)]
    public async Task<List<int>> SubirImagen(int id, IFormFile? archivo, [FromServices] ImagenesService imagenes, CancellationToken ct)
    {
        if (archivo is null)
            throw new BusinessRuleException("Adjunta la imagen en el campo \"archivo\".");
        if (archivo.Length > ProductoImagen.TamanoMaximo)
            throw new BusinessRuleException($"La imagen supera los {ProductoImagen.TamanoMaximo / 1024 / 1024} MB.");
        using var memoria = new MemoryStream();
        await archivo.CopyToAsync(memoria, ct);
        return await imagenes.SubirAsync(id, memoria.ToArray(), ct);
    }

    [HttpDelete("productos/{id:int}/imagenes/{imagenId:int}")]
    [Authorize(Roles = Roles.GestionInventario)]
    public Task<List<int>> EliminarImagen(int id, int imagenId, [FromServices] ImagenesService imagenes, CancellationToken ct) =>
        imagenes.EliminarAsync(id, imagenId, ct);

    [HttpPost("productos/{id:int}/imagenes/{imagenId:int}/principal")]
    [Authorize(Roles = Roles.GestionInventario)]
    public Task<List<int>> ImagenPrincipal(int id, int imagenId, [FromServices] ImagenesService imagenes, CancellationToken ct) =>
        imagenes.HacerPrincipalAsync(id, imagenId, ct);

    [HttpGet("productos/{id:int}/kardex")]
    public Task<KardexResponse> Kardex(int id, CancellationToken ct) => _inventario.KardexAsync(id, ct);

    [HttpPost("ajustes")]
    [Authorize(Roles = Roles.GestionInventario)]
    [ProducesResponseType<MovimientoResponse>(StatusCodes.Status201Created)]
    public async Task<IActionResult> Ajustar(AjusteInventarioRequest request, CancellationToken ct) =>
        StatusCode(StatusCodes.Status201Created, await _inventario.AjustarAsync(request, User.GetUsuarioId(), ct));
}

[ApiController]
[Route("api/compras")]
[Authorize(Roles = Roles.ConsultaCompras)]
public class ComprasController : ControllerBase
{
    private readonly TercerosService _terceros;
    private readonly CompraService _compras;

    public ComprasController(TercerosService terceros, CompraService compras)
    {
        _terceros = terceros;
        _compras = compras;
    }

    [HttpGet("proveedores")]
    public Task<List<ProveedorResponse>> ListarProveedores([FromQuery] string? buscar, [FromQuery] bool inactivos,
        CancellationToken ct) => _terceros.ListarProveedoresAsync(buscar, inactivos, ct);

    [HttpPost("proveedores")]
    [Authorize(Roles = Roles.GestionCompras)]
    [ProducesResponseType<ProveedorResponse>(StatusCodes.Status201Created)]
    public async Task<IActionResult> CrearProveedor(GuardarProveedorRequest request, CancellationToken ct) =>
        StatusCode(StatusCodes.Status201Created, await _terceros.CrearProveedorAsync(request, ct));

    [HttpPut("proveedores/{id:int}")]
    [Authorize(Roles = Roles.GestionCompras)]
    public Task<ProveedorResponse> EditarProveedor(int id, GuardarProveedorRequest request, CancellationToken ct) =>
        _terceros.EditarProveedorAsync(id, request, ct);

    [HttpGet("ordenes")]
    public Task<List<OrdenResumenResponse>> ListarOrdenes([FromQuery] string? estado, CancellationToken ct) =>
        _compras.ListarAsync(estado, ct);

    [HttpGet("ordenes/{id:int}")]
    [ProducesResponseType<OrdenResponse>(StatusCodes.Status200OK)]
    [ProducesResponseType<ErrorResponse>(StatusCodes.Status404NotFound)]
    public async Task<IActionResult> ObtenerOrden(int id, CancellationToken ct) =>
        await _compras.ObtenerAsync(id, ct) is { } o ? Ok(o) : NotFound(new ErrorResponse("Orden de compra no encontrada."));

    [HttpPost("ordenes")]
    [Authorize(Roles = Roles.GestionCompras)]
    [ProducesResponseType<OrdenResponse>(StatusCodes.Status201Created)]
    public async Task<IActionResult> CrearOrden(CrearOrdenRequest request, CancellationToken ct)
    {
        var orden = await _compras.CrearAsync(request, User.GetUsuarioId(), ct);
        return CreatedAtAction(nameof(ObtenerOrden), new { id = orden.Numero }, orden);
    }

    [HttpPost("ordenes/{id:int}/recibir")]
    [Authorize(Roles = Roles.RecepcionCompras)]
    public Task<OrdenResponse> Recibir(int id, RecibirOrdenRequest request, CancellationToken ct) =>
        _compras.RecibirAsync(id, request, User.GetUsuarioId(), ct);

    [HttpPost("ordenes/{id:int}/anular")]
    [Authorize(Roles = Roles.GestionCompras)]
    public Task<OrdenResponse> Anular(int id, CancellationToken ct) => _compras.AnularAsync(id, ct);
}

[ApiController]
[Route("api/contabilidad")]
[Authorize(Roles = Roles.Contabilidad)]
public class ContabilidadController : ControllerBase
{
    private readonly ContabilidadService _contabilidad;
    private readonly TimeProvider _time;

    public ContabilidadController(ContabilidadService contabilidad, TimeProvider time)
    {
        _contabilidad = contabilidad;
        _time = time;
    }

    [HttpGet("cuentas")]
    public Task<List<CuentaResponse>> ListarCuentas(CancellationToken ct) => _contabilidad.ListarCuentasAsync(ct);

    [HttpPost("cuentas")]
    [ProducesResponseType<CuentaResponse>(StatusCodes.Status201Created)]
    public async Task<IActionResult> CrearCuenta(GuardarCuentaRequest request, CancellationToken ct) =>
        StatusCode(StatusCodes.Status201Created, await _contabilidad.CrearCuentaAsync(request, ct));

    [HttpPut("cuentas/{id:int}")]
    public Task<CuentaResponse> EditarCuenta(int id, GuardarCuentaRequest request, CancellationToken ct) =>
        _contabilidad.EditarCuentaAsync(id, request, ct);

    /// <summary>Libro diario. Sin fechas: el mes en curso.</summary>
    [HttpGet("partidas")]
    public Task<List<PartidaResponse>> LibroDiario([FromQuery] DateOnly? desde, [FromQuery] DateOnly? hasta,
        [FromQuery] string? origen, CancellationToken ct)
    {
        var (d, h) = RangoPorDefecto.Resolver(desde, hasta, _time);
        return _contabilidad.LibroDiarioAsync(d, h, origen, ct);
    }

    [HttpGet("partidas/{id:int}")]
    [ProducesResponseType<PartidaResponse>(StatusCodes.Status200OK)]
    [ProducesResponseType<ErrorResponse>(StatusCodes.Status404NotFound)]
    public async Task<IActionResult> ObtenerPartida(int id, CancellationToken ct) =>
        await _contabilidad.ObtenerPartidaAsync(id, ct) is { } p ? Ok(p) : NotFound(new ErrorResponse("Partida no encontrada."));

    /// <summary>Partida manual (gastos, aportes de capital, etc.). Debe cuadrar.</summary>
    [HttpPost("partidas")]
    [ProducesResponseType<PartidaResponse>(StatusCodes.Status201Created)]
    public async Task<IActionResult> CrearPartida(CrearPartidaRequest request, CancellationToken ct)
    {
        var partida = await _contabilidad.CrearManualAsync(request, User.GetUsuarioId(), ct);
        return CreatedAtAction(nameof(ObtenerPartida), new { id = partida.Numero }, partida);
    }

    [HttpGet("reportes/mayor/{cuentaId:int}")]
    public Task<LibroMayorResponse> LibroMayor(int cuentaId, [FromQuery] DateOnly? desde, [FromQuery] DateOnly? hasta,
        CancellationToken ct)
    {
        var (d, h) = RangoPorDefecto.Resolver(desde, hasta, _time);
        return _contabilidad.LibroMayorAsync(cuentaId, d, h, ct);
    }

    [HttpGet("reportes/balance-comprobacion")]
    public Task<BalanceComprobacionResponse> BalanceComprobacion([FromQuery] DateOnly? desde, [FromQuery] DateOnly? hasta,
        CancellationToken ct)
    {
        var (d, h) = RangoPorDefecto.Resolver(desde, hasta, _time);
        return _contabilidad.BalanceComprobacionAsync(d, h, ct);
    }

    [HttpGet("reportes/estado-resultados")]
    public Task<EstadoResultadosResponse> EstadoResultados([FromQuery] DateOnly? desde, [FromQuery] DateOnly? hasta,
        CancellationToken ct)
    {
        var (d, h) = RangoPorDefecto.Resolver(desde, hasta, _time);
        return _contabilidad.EstadoResultadosAsync(d, h, ct);
    }

    [HttpGet("reportes/balance-general")]
    public Task<BalanceGeneralResponse> BalanceGeneral([FromQuery] DateOnly? al, CancellationToken ct) =>
        _contabilidad.BalanceGeneralAsync(al ?? Calendario.Hoy(_time), ct);
}

[ApiController]
[Route("api/panel")]
[Authorize(Roles = Roles.Panel)]
public class PanelController : ControllerBase
{
    private readonly PanelService _panel;

    public PanelController(PanelService panel) => _panel = panel;

    [HttpGet]
    public Task<PanelResponse> Resumen(CancellationToken ct) => _panel.ResumenAsync(ct);
}

/// <summary>Departamentos y municipios de Guatemala para los selectores de la entrega.</summary>
[ApiController]
[Route("api/geografia")]
[Authorize]
public class GeografiaController : ControllerBase
{
    [HttpGet]
    public IReadOnlyList<DepartamentoDto> Departamentos()
    {
        Response.Headers.CacheControl = "private, max-age=86400"; // no cambia: se puede guardar un día
        return Geografia.Departamentos;
    }
}

/// <summary>Pipeline de ventas: tablero por etapas y avance de etapa.</summary>
[ApiController]
[Route("api/pipeline")]
[Authorize(Roles = Roles.Pipeline)]
public class PipelineController : ControllerBase
{
    private readonly PipelineService _pipeline;

    public PipelineController(PipelineService pipeline) => _pipeline = pipeline;

    private string Rol => User.FindFirst(JwtClaims.Role)?.Value ?? "";

    [HttpGet]
    public Task<List<TarjetaPipelineResponse>> Tablero(CancellationToken ct) =>
        _pipeline.TableroAsync(User.GetUsuarioId(), Rol, ct);

    /// <summary>Detalle de la venta con su historial de etapas (bodega también la ve, para despachar).</summary>
    [HttpGet("{id:int}")]
    [ProducesResponseType<PedidoResponse>(StatusCodes.Status200OK)]
    [ProducesResponseType<ErrorResponse>(StatusCodes.Status404NotFound)]
    public async Task<IActionResult> Obtener(int id, [FromServices] Pedidos.Api.Services.PedidoService pedidos, CancellationToken ct) =>
        await pedidos.ObtenerAsync(id, User.GetUsuarioId(), PipelineService.VeTodas(Rol), ct) is { } p
            ? Ok(p)
            : NotFound(new ErrorResponse("Venta no encontrada."));

    [HttpPost("{id:int}/avanzar")]
    public async Task<MensajeResponse> Avanzar(int id, AvanzarEstadoRequest request, CancellationToken ct)
    {
        var nuevo = await _pipeline.AvanzarAsync(id, User.GetUsuarioId(), Rol, request.Nota, ct);
        return new MensajeResponse($"La venta A-{id} pasó a \"{EstadosVenta.Nombre(nuevo)}\".");
    }
}

/// <summary>Reportes de ventas. El vendedor ve solo sus ventas; ADMIN y CONTADOR, todas.</summary>
[ApiController]
[Route("api/reportes")]
[Authorize(Roles = Roles.ConsultaVentas)]
public class ReportesController : ControllerBase
{
    private readonly ReporteVentasService _reportes;
    private readonly PronosticoService _pronostico;
    private readonly TimeProvider _time;

    public ReportesController(ReporteVentasService reportes, PronosticoService pronostico, TimeProvider time)
    {
        _reportes = reportes;
        _pronostico = pronostico;
        _time = time;
    }

    private bool VeTodas => User.IsInRole(Roles.Admin) || User.IsInRole(Roles.Contador);

    [HttpGet("ventas")]
    public Task<ReporteVentasResponse> Ventas([FromQuery] DateOnly? desde, [FromQuery] DateOnly? hasta, CancellationToken ct)
    {
        var (d, h) = RangoPorDefecto.Resolver(desde, hasta, _time);
        return _reportes.GenerarAsync(d, h, User.GetUsuarioId(), VeTodas, ct);
    }

    /// <summary>Pronóstico según el pipeline: cerrado + total de cada etapa abierta por su probabilidad de cierre.</summary>
    [HttpGet("pronostico")]
    public Task<PronosticoResponse> Pronostico([FromQuery] DateOnly? desde, [FromQuery] DateOnly? hasta, CancellationToken ct)
    {
        var (d, h) = RangoPorDefecto.Resolver(desde, hasta, _time);
        return _pronostico.GenerarAsync(d, h, User.GetUsuarioId(), VeTodas, ct);
    }

    /// <summary>Cambia la probabilidad de cierre de las etapas (solo administración).</summary>
    [HttpPut("pronostico/probabilidades")]
    [Authorize(Roles = Roles.Admin)]
    public async Task<MensajeResponse> Probabilidades(ActualizarProbabilidadesRequest request, CancellationToken ct)
    {
        await _pronostico.ActualizarProbabilidadesAsync(request, User.GetUsuarioId(), ct);
        return new MensajeResponse("Se guardaron las probabilidades de cierre.");
    }
}
