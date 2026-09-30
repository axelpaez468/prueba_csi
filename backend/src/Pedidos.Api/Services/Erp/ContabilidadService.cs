using System.Text.RegularExpressions;
using Microsoft.EntityFrameworkCore;
using Pedidos.Api.Data;
using Pedidos.Api.Domain;
using Pedidos.Api.Dtos;
using Pedidos.Api.Errors;

namespace Pedidos.Api.Services.Erp;

/// <summary>Línea de una partida automática, identificada por el código de la cuenta.</summary>
public record LineaAsiento(string CodigoCuenta, decimal Debe, decimal Haber)
{
    public static LineaAsiento Cargo(string cuenta, decimal monto) => new(cuenta, monto, 0);
    public static LineaAsiento Abono(string cuenta, decimal monto) => new(cuenta, 0, monto);
}

/// <summary>
/// Catálogo de cuentas, libro diario y estados financieros. Las ventas, compras y ajustes de inventario
/// registran su partida con <see cref="RegistrarAutomaticaAsync"/> dentro de su misma transacción: si la
/// operación falla no queda partida, y si la partida no cuadra la operación no se guarda.
/// </summary>
public partial class ContabilidadService
{
    public const int LineasPorPartidaMax = 50;

    private readonly AppDbContext _db;
    private readonly TimeProvider _time;

    public ContabilidadService(AppDbContext db, TimeProvider time)
    {
        _db = db;
        _time = time;
    }

    [GeneratedRegex(@"^[1-6]\d{3,9}$")]
    private static partial Regex RegexCodigo();

    // ---------- Partidas automáticas ----------

    /// <summary>Agrega la partida al contexto (la guarda el SaveChanges de quien la llama). Omite líneas en cero.</summary>
    public async Task<Partida> RegistrarAutomaticaAsync(string origen, long referenciaId, string concepto, int? usuarioId,
        IEnumerable<LineaAsiento> lineas, CancellationToken ct)
    {
        var validas = lineas.Where(l => l.Debe != 0 || l.Haber != 0).ToList();
        var codigos = validas.Select(l => l.CodigoCuenta).Distinct().ToList();
        var cuentas = await _db.CuentasContables.AsNoTracking()
            .Where(c => codigos.Contains(c.Codigo))
            .ToDictionaryAsync(c => c.Codigo, c => c.Id, ct);

        var faltante = codigos.FirstOrDefault(c => !cuentas.ContainsKey(c));
        if (faltante is not null)
            throw new InvalidOperationException($"Falta la cuenta contable del sistema {faltante}.");

        var partida = Construir(Calendario.Hoy(_time), concepto, origen, referenciaId, usuarioId,
            validas.Select(l => (cuentas[l.CodigoCuenta], l.Debe, l.Haber)).ToList());
        if (partida.Detalles.Sum(d => d.Debe) != partida.Detalles.Sum(d => d.Haber))
            throw new InvalidOperationException($"La partida automática de {origen} {referenciaId} no cuadra.");

        _db.Partidas.Add(partida);
        return partida;
    }

    // ---------- Partidas manuales ----------

    public async Task<PartidaResponse> CrearManualAsync(CrearPartidaRequest r, int usuarioId, CancellationToken ct)
    {
        var hoy = Calendario.Hoy(_time);
        var fecha = r.Fecha ?? hoy;
        if (fecha > hoy)
            throw new BusinessRuleException("La fecha de la partida no puede ser futura.");
        var concepto = Contacto.Requerido(r.Concepto, 5, 200, "El concepto");

        var lineas = r.Lineas ?? new();
        if (lineas.Count < 2)
            throw new BusinessRuleException("La partida debe tener al menos dos líneas (un cargo y un abono).");
        if (lineas.Count > LineasPorPartidaMax)
            throw new BusinessRuleException($"Una partida admite como máximo {LineasPorPartidaMax} líneas.");
        foreach (var (l, i) in lineas.Select((l, i) => (l, i + 1)))
        {
            if (l.Debe < 0 || l.Haber < 0 || (l.Debe > 0) == (l.Haber > 0))
                throw new BusinessRuleException($"La línea {i} debe tener un monto en el debe o en el haber (solo uno).");
            if (!Montos.TieneCentavosValidos(l.Debe) || !Montos.TieneCentavosValidos(l.Haber) ||
                l.Debe > Montos.Maximo || l.Haber > Montos.Maximo)
                throw new BusinessRuleException($"El monto de la línea {i} no es válido (máximo dos decimales).");
        }

        var ids = lineas.Select(l => l.CuentaId).Distinct().ToList();
        var activas = await _db.CuentasContables.AsNoTracking()
            .Where(c => ids.Contains(c.Id) && c.Activa).Select(c => c.Id).ToListAsync(ct);
        var invalida = ids.FirstOrDefault(id => !activas.Contains(id));
        if (invalida != 0)
            throw new BusinessRuleException($"La cuenta {invalida} no existe o está inactiva.");

        var debe = lineas.Sum(l => l.Debe);
        var haber = lineas.Sum(l => l.Haber);
        if (debe != haber)
            throw new BusinessRuleException(
                $"La partida no cuadra: el debe suma {debe:N2} y el haber {haber:N2} (diferencia {Math.Abs(debe - haber):N2}).");

        var partida = Construir(fecha, concepto, OrigenesPartida.Manual, null, usuarioId,
            lineas.Select(l => (l.CuentaId, l.Debe, l.Haber)).ToList());
        _db.Partidas.Add(partida);
        await _db.SaveChangesAsync(ct);
        return (await ObtenerPartidaAsync(partida.Id, ct))!;
    }

    private Partida Construir(DateOnly fecha, string concepto, string origen, long? referenciaId, int? usuarioId,
        List<(int CuentaId, decimal Debe, decimal Haber)> lineas) => new()
    {
        Fecha = fecha,
        Concepto = concepto.Length > 200 ? concepto[..200] : concepto,
        Origen = origen,
        ReferenciaId = referenciaId,
        UsuarioId = usuarioId,
        CreadoEn = _time.GetUtcNow().UtcDateTime,
        Total = lineas.Sum(l => l.Debe),
        Detalles = lineas.Select(l => new PartidaDetalle { CuentaId = l.CuentaId, Debe = l.Debe, Haber = l.Haber }).ToList()
    };

    // ---------- Catálogo de cuentas ----------

    public async Task<List<CuentaResponse>> ListarCuentasAsync(CancellationToken ct)
    {
        var sumas = await SumasPorCuentaAsync(null, null, ct);
        var cuentas = await _db.CuentasContables.AsNoTracking().OrderBy(c => c.Codigo).ToListAsync(ct);
        return cuentas.Select(c => MapearCuenta(c, sumas)).ToList();
    }

    public async Task<CuentaResponse> CrearCuentaAsync(GuardarCuentaRequest r, CancellationToken ct)
    {
        var codigo = (r.Codigo ?? "").Trim();
        if (!RegexCodigo().IsMatch(codigo))
            throw new BusinessRuleException(
                "El código debe tener de 4 a 10 dígitos y empezar con 1 (activo), 2 (pasivo), 3 (capital), 4 (ingreso), 5 (costo) o 6 (gasto).");
        if (await _db.CuentasContables.AnyAsync(c => c.Codigo == codigo, ct))
            throw new BusinessRuleException("Ya existe una cuenta con ese código.");

        var cuenta = new CuentaContable
        {
            Codigo = codigo,
            Nombre = Contacto.Requerido(r.Nombre, 3, 100, "El nombre de la cuenta"),
            Tipo = TiposCuenta.DesdeCodigo(codigo)!,
            Activa = r.Activa ?? true
        };
        _db.CuentasContables.Add(cuenta);
        await _db.SaveChangesAsync(ct);
        return MapearCuenta(cuenta, new());
    }

    public async Task<CuentaResponse> EditarCuentaAsync(int id, GuardarCuentaRequest r, CancellationToken ct)
    {
        var cuenta = await _db.CuentasContables.FirstOrDefaultAsync(c => c.Id == id, ct)
                     ?? throw new NoEncontradoException("Cuenta contable no encontrada.");
        cuenta.Nombre = Contacto.Requerido(r.Nombre, 3, 100, "El nombre de la cuenta");
        var activa = r.Activa ?? cuenta.Activa;
        if (!activa && CuentasSistema.Todas.Contains(cuenta.Codigo))
            throw new BusinessRuleException("Esta cuenta la usan las partidas automáticas y no se puede desactivar.");
        cuenta.Activa = activa;
        await _db.SaveChangesAsync(ct);
        return MapearCuenta(cuenta, await SumasPorCuentaAsync(null, null, ct));
    }

    // ---------- Libro diario y mayor ----------

    public async Task<List<PartidaResponse>> LibroDiarioAsync(DateOnly desde, DateOnly hasta, string? origen, CancellationToken ct)
    {
        Calendario.RangoUtc(desde, hasta); // valida el rango
        var q = _db.Partidas.AsNoTracking().Where(p => p.Fecha >= desde && p.Fecha <= hasta);
        if (!string.IsNullOrWhiteSpace(origen)) q = q.Where(p => p.Origen == origen.Trim().ToUpperInvariant());
        var partidas = await q.OrderBy(p => p.Fecha).ThenBy(p => p.Id).Take(1000)
            .Include(p => p.Detalles).ThenInclude(d => d.Cuenta)
            .AsSplitQuery()
            .ToListAsync(ct);
        return partidas.Select(MapearPartida).ToList();
    }

    public async Task<PartidaResponse?> ObtenerPartidaAsync(int id, CancellationToken ct)
    {
        var p = await _db.Partidas.AsNoTracking()
            .Include(x => x.Detalles).ThenInclude(d => d.Cuenta)
            .FirstOrDefaultAsync(x => x.Id == id, ct);
        return p is null ? null : MapearPartida(p);
    }

    public async Task<LibroMayorResponse> LibroMayorAsync(int cuentaId, DateOnly desde, DateOnly hasta, CancellationToken ct)
    {
        Calendario.RangoUtc(desde, hasta);
        var cuenta = await _db.CuentasContables.AsNoTracking().FirstOrDefaultAsync(c => c.Id == cuentaId, ct)
                     ?? throw new NoEncontradoException("Cuenta contable no encontrada.");
        var deudora = TiposCuenta.EsDeudora(cuenta.Tipo);
        decimal Saldo(decimal debe, decimal haber) => deudora ? debe - haber : haber - debe;

        var anteriores = await SumasPorCuentaAsync(null, desde.AddDays(-1), ct, cuentaId);
        var (debeAntes, haberAntes) = anteriores.GetValueOrDefault(cuentaId);
        var saldoInicial = Saldo(debeAntes, haberAntes);

        var movimientos = await _db.PartidaDetalles.AsNoTracking()
            .Where(d => d.CuentaId == cuentaId)
            .Join(_db.Partidas.Where(p => p.Fecha >= desde && p.Fecha <= hasta), d => d.PartidaId, p => p.Id,
                (d, p) => new { p.Fecha, PartidaId = p.Id, p.Concepto, d.Debe, d.Haber, d.Id })
            .OrderBy(x => x.Fecha).ThenBy(x => x.PartidaId).ThenBy(x => x.Id)
            .Take(2000)
            .ToListAsync(ct);

        var saldo = saldoInicial;
        var filas = movimientos.Select(m =>
        {
            saldo += Saldo(m.Debe, m.Haber);
            return new MovimientoMayorResponse(m.Fecha, m.PartidaId, m.Concepto, m.Debe, m.Haber, saldo);
        }).ToList();

        var total = await SumasPorCuentaAsync(null, null, ct, cuentaId);
        return new LibroMayorResponse(MapearCuenta(cuenta, total), desde, hasta, saldoInicial,
            movimientos.Sum(m => m.Debe), movimientos.Sum(m => m.Haber), saldo, filas);
    }

    // ---------- Estados financieros ----------

    public async Task<BalanceComprobacionResponse> BalanceComprobacionAsync(DateOnly desde, DateOnly hasta, CancellationToken ct)
    {
        Calendario.RangoUtc(desde, hasta);
        var sumas = await SumasPorCuentaAsync(desde, hasta, ct);
        var cuentas = await _db.CuentasContables.AsNoTracking().OrderBy(c => c.Codigo).ToListAsync(ct);

        var filas = cuentas.Where(c => sumas.ContainsKey(c.Id)).Select(c =>
        {
            var (debe, haber) = sumas[c.Id];
            var neto = debe - haber;
            return new FilaBalanceComprobacion(c.Codigo, c.Nombre, c.Tipo, debe, haber,
                neto > 0 ? neto : 0, neto < 0 ? -neto : 0);
        }).ToList();

        var totalDebe = filas.Sum(f => f.Debe);
        var totalHaber = filas.Sum(f => f.Haber);
        var deudor = filas.Sum(f => f.SaldoDeudor);
        var acreedor = filas.Sum(f => f.SaldoAcreedor);
        return new BalanceComprobacionResponse(desde, hasta, filas, totalDebe, totalHaber, deudor, acreedor,
            totalDebe == totalHaber && deudor == acreedor);
    }

    public async Task<EstadoResultadosResponse> EstadoResultadosAsync(DateOnly desde, DateOnly hasta, CancellationToken ct)
    {
        Calendario.RangoUtc(desde, hasta);
        var renglones = await RenglonesAsync(desde, hasta, ct);
        List<RenglonReporte> De(string tipo) => renglones.Where(r => r.Tipo == tipo).Select(r => r.Renglon).ToList();

        var ingresos = De(TiposCuenta.Ingreso);
        var costos = De(TiposCuenta.Costo);
        var gastos = De(TiposCuenta.Gasto);
        var totalIngresos = ingresos.Sum(r => r.Monto);
        var totalCostos = costos.Sum(r => r.Monto);
        var totalGastos = gastos.Sum(r => r.Monto);
        var bruta = totalIngresos - totalCostos;
        return new EstadoResultadosResponse(desde, hasta, ingresos, totalIngresos, costos, totalCostos, bruta,
            gastos, totalGastos, bruta - totalGastos);
    }

    /// <summary>
    /// Balance general a una fecha. Como no hay cierre contable, el resultado del ejercicio es la utilidad
    /// acumulada de todas las partidas hasta esa fecha y se presenta dentro del capital.
    /// </summary>
    public async Task<BalanceGeneralResponse> BalanceGeneralAsync(DateOnly al, CancellationToken ct)
    {
        var renglones = await RenglonesAsync(null, al, ct);
        List<RenglonReporte> De(string tipo) =>
            renglones.Where(r => r.Tipo == tipo && r.Renglon.Monto != 0).Select(r => r.Renglon).ToList();
        decimal Total(string tipo) => renglones.Where(r => r.Tipo == tipo).Sum(r => r.Renglon.Monto);

        var activos = De(TiposCuenta.Activo);
        var pasivos = De(TiposCuenta.Pasivo);
        var capital = De(TiposCuenta.Capital);
        var totalActivos = activos.Sum(r => r.Monto);
        var totalPasivos = pasivos.Sum(r => r.Monto);
        var resultado = Total(TiposCuenta.Ingreso) - Total(TiposCuenta.Costo) - Total(TiposCuenta.Gasto);
        var totalCapital = capital.Sum(r => r.Monto) + resultado;
        return new BalanceGeneralResponse(al, activos, totalActivos, pasivos, totalPasivos, capital, resultado,
            totalCapital, totalPasivos + totalCapital, totalActivos == totalPasivos + totalCapital);
    }

    // ---------- Auxiliares ----------

    /// <summary>Saldo de cada cuenta según su naturaleza, en el rango indicado.</summary>
    private async Task<List<(string Tipo, RenglonReporte Renglon)>> RenglonesAsync(DateOnly? desde, DateOnly? hasta, CancellationToken ct)
    {
        var sumas = await SumasPorCuentaAsync(desde, hasta, ct);
        var cuentas = await _db.CuentasContables.AsNoTracking().OrderBy(c => c.Codigo).ToListAsync(ct);
        return cuentas.Where(c => sumas.ContainsKey(c.Id)).Select(c =>
        {
            var (debe, haber) = sumas[c.Id];
            var monto = TiposCuenta.EsDeudora(c.Tipo) ? debe - haber : haber - debe;
            return (c.Tipo, new RenglonReporte(c.Codigo, c.Nombre, monto));
        }).ToList();
    }

    /// <summary>Suma del debe y del haber por cuenta (agregado en la base de datos).</summary>
    private async Task<Dictionary<int, (decimal Debe, decimal Haber)>> SumasPorCuentaAsync(
        DateOnly? desde, DateOnly? hasta, CancellationToken ct, int? cuentaId = null)
    {
        var partidas = _db.Partidas.AsNoTracking();
        if (desde is { } d) partidas = partidas.Where(p => p.Fecha >= d);
        if (hasta is { } h) partidas = partidas.Where(p => p.Fecha <= h);
        var detalles = _db.PartidaDetalles.AsNoTracking();
        if (cuentaId is { } id) detalles = detalles.Where(x => x.CuentaId == id);

        var lineas = detalles.Join(partidas, x => x.PartidaId, p => p.Id, (x, _) => x);

        // SQLite (solo en las pruebas) no suma decimales: ahí se agrega en memoria. SQL Server lo hace en la BD.
        if (_db.Database.ProviderName == "Microsoft.EntityFrameworkCore.Sqlite")
        {
            var todas = await lineas.Select(x => new { x.CuentaId, x.Debe, x.Haber }).ToListAsync(ct);
            return todas.GroupBy(x => x.CuentaId).ToDictionary(g => g.Key, g => (g.Sum(x => x.Debe), g.Sum(x => x.Haber)));
        }

        var filas = await lineas
            .GroupBy(x => x.CuentaId)
            .Select(g => new { CuentaId = g.Key, Debe = g.Sum(x => x.Debe), Haber = g.Sum(x => x.Haber) })
            .ToListAsync(ct);
        return filas.ToDictionary(f => f.CuentaId, f => (f.Debe, f.Haber));
    }

    private static CuentaResponse MapearCuenta(CuentaContable c, Dictionary<int, (decimal Debe, decimal Haber)> sumas)
    {
        var (debe, haber) = sumas.GetValueOrDefault(c.Id);
        var saldo = TiposCuenta.EsDeudora(c.Tipo) ? debe - haber : haber - debe;
        return new CuentaResponse(c.Id, c.Codigo, c.Nombre, c.Tipo, c.Activa, CuentasSistema.Todas.Contains(c.Codigo), saldo);
    }

    private static PartidaResponse MapearPartida(Partida p) => new(
        p.Id, p.Fecha, p.Concepto, p.Origen, p.ReferenciaId, p.Total, p.CreadoEn,
        p.Detalles
            .OrderBy(d => d.Haber > 0) // primero los cargos, después los abonos
            .ThenBy(d => d.Id)
            .Select(d => new LineaPartidaResponse(d.CuentaId, d.Cuenta!.Codigo, d.Cuenta.Nombre, d.Debe, d.Haber))
            .ToList());
}
