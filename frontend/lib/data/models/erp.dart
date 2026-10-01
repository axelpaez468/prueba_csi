import '../../core/util/formatters.dart';
import 'producto.dart';

double _d(Object? v) => (v as num?)?.toDouble() ?? 0;

// ---------- Clientes y proveedores ----------

class Cliente {
  const Cliente({
    required this.id,
    required this.nit,
    required this.nitFormateado,
    required this.nombre,
    this.direccion,
    this.telefono,
    this.email,
    required this.activo,
    required this.esConsumidorFinal,
  });

  final int id;
  final String nit;
  final String nitFormateado;
  final String nombre;
  final String? direccion;
  final String? telefono;
  final String? email;
  final bool activo;
  final bool esConsumidorFinal;

  factory Cliente.fromJson(Map<String, dynamic> j) => Cliente(
        id: j['id'] as int,
        nit: j['nit'] as String,
        nitFormateado: j['nitFormateado'] as String,
        nombre: j['nombre'] as String,
        direccion: j['direccion'] as String?,
        telefono: j['telefono'] as String?,
        email: j['email'] as String?,
        activo: j['activo'] as bool,
        esConsumidorFinal: j['esConsumidorFinal'] as bool,
      );
}

class Proveedor {
  const Proveedor({
    required this.id,
    required this.nit,
    required this.nitFormateado,
    required this.nombre,
    this.contacto,
    this.telefono,
    this.email,
    this.direccion,
    required this.activo,
  });

  final int id;
  final String nit;
  final String nitFormateado;
  final String nombre;
  final String? contacto;
  final String? telefono;
  final String? email;
  final String? direccion;
  final bool activo;

  factory Proveedor.fromJson(Map<String, dynamic> j) => Proveedor(
        id: j['id'] as int,
        nit: j['nit'] as String,
        nitFormateado: j['nitFormateado'] as String,
        nombre: j['nombre'] as String,
        contacto: j['contacto'] as String?,
        telefono: j['telefono'] as String?,
        email: j['email'] as String?,
        direccion: j['direccion'] as String?,
        activo: j['activo'] as bool,
      );
}

/// "+50255550101" → "+502 5555 0101"; los 8 dígitos locales para editar.
String telefonoLegible(String? telefono) {
  if (telefono == null) return '';
  final l = telefono.startsWith('+502') ? telefono.substring(4) : telefono;
  return l.length == 8 ? '+502 ${l.substring(0, 4)} ${l.substring(4)}' : telefono;
}

String telefonoLocal(String? telefono) =>
    telefono == null ? '' : (telefono.startsWith('+502') ? telefono.substring(4) : telefono);

// ---------- Ventas ----------

class VentaResumen {
  const VentaResumen({
    required this.numero,
    required this.serie,
    required this.fecha,
    required this.clienteNit,
    required this.clienteNombre,
    required this.vendedor,
    required this.formaPago,
    required this.productos,
    required this.total,
    this.estado = 'ENTREGADO',
    this.departamento,
  });

  final int numero;
  final String serie;
  final DateTime fecha;
  final String clienteNit;
  final String clienteNombre;
  final String vendedor;
  final String formaPago;
  final int productos;
  final double total;
  final String estado;
  final String? departamento;

  factory VentaResumen.fromJson(Map<String, dynamic> j) => VentaResumen(
        numero: j['numero'] as int,
        serie: j['serie'] as String,
        fecha: DateTime.parse(j['fecha'] as String),
        clienteNit: j['clienteNit'] as String,
        clienteNombre: j['clienteNombre'] as String,
        vendedor: j['vendedor'] as String,
        formaPago: j['formaPago'] as String,
        productos: j['productos'] as int,
        total: _d(j['total']),
        estado: (j['estado'] as String?) ?? 'ENTREGADO',
        departamento: j['departamento'] as String?,
      );
}

String formaPagoLegible(String forma) => switch (forma) {
      'EFECTIVO' => 'Efectivo',
      'TARJETA' => 'Tarjeta',
      'TRANSFERENCIA' => 'Transferencia',
      _ => forma,
    };

// ---------- Inventario ----------

class ProductoInventario {
  const ProductoInventario({
    required this.id,
    required this.codigo,
    required this.nombre,
    required this.precio,
    required this.stock,
    required this.stockMinimo,
    required this.costoPromedio,
    required this.valorInventario,
    required this.activo,
    required this.bajoMinimo,
    this.margen,
    this.marca,
    this.categoria,
    this.descripcion,
    this.garantiaMeses = 0,
    this.especificaciones = const [],
    this.imagenes = const [],
  });

  final int id;
  final String codigo;
  final String nombre;
  final double precio;
  final int stock;
  final int stockMinimo;
  final double costoPromedio;
  final double valorInventario;
  final bool activo;
  final bool bajoMinimo;
  final double? margen;
  final String? marca;
  final String? categoria;
  final String? descripcion;
  final int garantiaMeses;
  final List<Especificacion> especificaciones;

  /// Ids de las fotos, en orden (la primera es la principal).
  final List<int> imagenes;

  /// Para mostrarlo con los widgets del catálogo (foto, nombre, precio).
  Producto get comoProducto => Producto(
      id: id, codigo: codigo, nombre: nombre, precio: precio, stock: stock, marca: marca, categoria: categoria,
      imagenId: imagenes.isEmpty ? null : imagenes.first);

  factory ProductoInventario.fromJson(Map<String, dynamic> j) => ProductoInventario(
        id: j['id'] as int,
        codigo: j['codigo'] as String,
        nombre: j['nombre'] as String,
        precio: _d(j['precio']),
        stock: j['stock'] as int,
        stockMinimo: j['stockMinimo'] as int,
        costoPromedio: _d(j['costoPromedio']),
        valorInventario: _d(j['valorInventario']),
        activo: j['activo'] as bool,
        bajoMinimo: j['bajoMinimo'] as bool,
        margen: (j['margen'] as num?)?.toDouble(),
        marca: j['marca'] as String?,
        categoria: j['categoria'] as String?,
        descripcion: j['descripcion'] as String?,
        garantiaMeses: (j['garantiaMeses'] as int?) ?? 0,
        especificaciones: Especificacion.lista(j['especificaciones']),
        imagenes: ((j['imagenes'] as List?) ?? const []).cast<int>(),
      );
}

class MovimientoInventario {
  const MovimientoInventario({
    required this.id,
    required this.fecha,
    required this.tipo,
    required this.cantidad,
    required this.costoUnitario,
    required this.saldo,
    required this.costoPromedio,
    required this.referencia,
    this.usuario,
  });

  final int id;
  final DateTime fecha;
  final String tipo;
  final int cantidad;
  final double costoUnitario;
  final int saldo;
  final double costoPromedio;
  final String referencia;
  final String? usuario;

  bool get esEntrada => cantidad > 0;

  String get tipoLegible => switch (tipo) {
        'INICIAL' => 'Inventario inicial',
        'VENTA' => 'Venta',
        'COMPRA' => 'Compra',
        'AJUSTE_ENTRADA' => 'Ajuste (entrada)',
        'AJUSTE_SALIDA' => 'Ajuste (salida)',
        _ => tipo,
      };

  factory MovimientoInventario.fromJson(Map<String, dynamic> j) => MovimientoInventario(
        id: j['id'] as int,
        fecha: DateTime.parse(j['fecha'] as String),
        tipo: j['tipo'] as String,
        cantidad: j['cantidad'] as int,
        costoUnitario: _d(j['costoUnitario']),
        saldo: j['saldo'] as int,
        costoPromedio: _d(j['costoPromedio']),
        referencia: j['referencia'] as String,
        usuario: j['usuario'] as String?,
      );
}

class Kardex {
  const Kardex(this.producto, this.movimientos);

  final ProductoInventario producto;
  final List<MovimientoInventario> movimientos;

  factory Kardex.fromJson(Map<String, dynamic> j) => Kardex(
        ProductoInventario.fromJson(j['producto'] as Map<String, dynamic>),
        (j['movimientos'] as List).map((m) => MovimientoInventario.fromJson(m as Map<String, dynamic>)).toList(),
      );
}

// ---------- Compras ----------

class OrdenResumen {
  const OrdenResumen({
    required this.numero,
    required this.fecha,
    required this.estado,
    required this.proveedorNombre,
    required this.productos,
    required this.total,
    this.facturaProveedor,
  });

  final int numero;
  final DateTime fecha;
  final String estado;
  final String proveedorNombre;
  final int productos;
  final double total;
  final String? facturaProveedor;

  factory OrdenResumen.fromJson(Map<String, dynamic> j) => OrdenResumen(
        numero: j['numero'] as int,
        fecha: DateTime.parse(j['fecha'] as String),
        estado: j['estado'] as String,
        proveedorNombre: j['proveedorNombre'] as String,
        productos: j['productos'] as int,
        total: _d(j['total']),
        facturaProveedor: j['facturaProveedor'] as String?,
      );
}

class LineaOrden {
  const LineaOrden({
    required this.productoId,
    required this.codigo,
    required this.nombre,
    required this.cantidad,
    required this.costoUnitario,
    required this.subtotal,
  });

  final int productoId;
  final String codigo;
  final String nombre;
  final int cantidad;
  final double costoUnitario;
  final double subtotal;

  factory LineaOrden.fromJson(Map<String, dynamic> j) => LineaOrden(
        productoId: j['productoId'] as int,
        codigo: j['codigo'] as String,
        nombre: j['nombre'] as String,
        cantidad: j['cantidad'] as int,
        costoUnitario: _d(j['costoUnitario']),
        subtotal: _d(j['subtotal']),
      );
}

class OrdenCompra {
  const OrdenCompra({
    required this.numero,
    required this.fecha,
    required this.estado,
    required this.proveedorId,
    required this.proveedorNit,
    required this.proveedorNombre,
    required this.subtotal,
    required this.iva,
    required this.total,
    this.observaciones,
    required this.creadaPor,
    this.fechaRecepcion,
    this.recibidaPor,
    this.facturaProveedor,
    required this.lineas,
  });

  final int numero;
  final DateTime fecha;
  final String estado;
  final int proveedorId;
  final String proveedorNit;
  final String proveedorNombre;
  final double subtotal;
  final double iva;
  final double total;
  final String? observaciones;
  final String creadaPor;
  final DateTime? fechaRecepcion;
  final String? recibidaPor;
  final String? facturaProveedor;
  final List<LineaOrden> lineas;

  bool get pendiente => estado == 'PENDIENTE';

  factory OrdenCompra.fromJson(Map<String, dynamic> j) => OrdenCompra(
        numero: j['numero'] as int,
        fecha: DateTime.parse(j['fecha'] as String),
        estado: j['estado'] as String,
        proveedorId: j['proveedorId'] as int,
        proveedorNit: j['proveedorNit'] as String,
        proveedorNombre: j['proveedorNombre'] as String,
        subtotal: _d(j['subtotal']),
        iva: _d(j['iva']),
        total: _d(j['total']),
        observaciones: j['observaciones'] as String?,
        creadaPor: j['creadaPor'] as String,
        fechaRecepcion: j['fechaRecepcion'] == null ? null : DateTime.parse(j['fechaRecepcion'] as String),
        recibidaPor: j['recibidaPor'] as String?,
        facturaProveedor: j['facturaProveedor'] as String?,
        lineas: (j['lineas'] as List).map((l) => LineaOrden.fromJson(l as Map<String, dynamic>)).toList(),
      );
}

// ---------- Contabilidad ----------

class CuentaContable {
  const CuentaContable({
    required this.id,
    required this.codigo,
    required this.nombre,
    required this.tipo,
    required this.activa,
    required this.esSistema,
    required this.saldo,
  });

  final int id;
  final String codigo;
  final String nombre;
  final String tipo;
  final bool activa;
  final bool esSistema;
  final double saldo;

  String get descripcion => '$codigo · $nombre';

  factory CuentaContable.fromJson(Map<String, dynamic> j) => CuentaContable(
        id: j['id'] as int,
        codigo: j['codigo'] as String,
        nombre: j['nombre'] as String,
        tipo: j['tipo'] as String,
        activa: j['activa'] as bool,
        esSistema: j['esSistema'] as bool,
        saldo: _d(j['saldo']),
      );
}

String tipoCuentaLegible(String tipo) => switch (tipo) {
      'ACTIVO' => 'Activo',
      'PASIVO' => 'Pasivo',
      'CAPITAL' => 'Capital',
      'INGRESO' => 'Ingreso',
      'COSTO' => 'Costo',
      'GASTO' => 'Gasto',
      _ => tipo,
    };

class LineaPartida {
  const LineaPartida({required this.cuentaId, required this.codigo, required this.cuenta, required this.debe, required this.haber});

  final int cuentaId;
  final String codigo;
  final String cuenta;
  final double debe;
  final double haber;

  factory LineaPartida.fromJson(Map<String, dynamic> j) => LineaPartida(
        cuentaId: j['cuentaId'] as int,
        codigo: j['codigo'] as String,
        cuenta: j['cuenta'] as String,
        debe: _d(j['debe']),
        haber: _d(j['haber']),
      );
}

class Partida {
  const Partida({
    required this.numero,
    required this.fecha,
    required this.concepto,
    required this.origen,
    required this.total,
    required this.lineas,
  });

  final int numero;
  final DateTime fecha;
  final String concepto;
  final String origen;
  final double total;
  final List<LineaPartida> lineas;

  factory Partida.fromJson(Map<String, dynamic> j) => Partida(
        numero: j['numero'] as int,
        fecha: leerDia(j['fecha'] as String),
        concepto: j['concepto'] as String,
        origen: j['origen'] as String,
        total: _d(j['total']),
        lineas: (j['lineas'] as List).map((l) => LineaPartida.fromJson(l as Map<String, dynamic>)).toList(),
      );
}

class MovimientoMayor {
  const MovimientoMayor(this.fecha, this.partida, this.concepto, this.debe, this.haber, this.saldo);

  final DateTime fecha;
  final int partida;
  final String concepto;
  final double debe;
  final double haber;
  final double saldo;

  factory MovimientoMayor.fromJson(Map<String, dynamic> j) => MovimientoMayor(leerDia(j['fecha'] as String),
      j['partida'] as int, j['concepto'] as String, _d(j['debe']), _d(j['haber']), _d(j['saldo']));
}

class LibroMayor {
  const LibroMayor(this.cuenta, this.saldoInicial, this.totalDebe, this.totalHaber, this.saldoFinal, this.movimientos);

  final CuentaContable cuenta;
  final double saldoInicial;
  final double totalDebe;
  final double totalHaber;
  final double saldoFinal;
  final List<MovimientoMayor> movimientos;

  factory LibroMayor.fromJson(Map<String, dynamic> j) => LibroMayor(
        CuentaContable.fromJson(j['cuenta'] as Map<String, dynamic>),
        _d(j['saldoInicial']),
        _d(j['totalDebe']),
        _d(j['totalHaber']),
        _d(j['saldoFinal']),
        (j['movimientos'] as List).map((m) => MovimientoMayor.fromJson(m as Map<String, dynamic>)).toList(),
      );
}

class FilaBalance {
  const FilaBalance(this.codigo, this.cuenta, this.tipo, this.debe, this.haber, this.saldoDeudor, this.saldoAcreedor);

  final String codigo;
  final String cuenta;
  final String tipo;
  final double debe;
  final double haber;
  final double saldoDeudor;
  final double saldoAcreedor;

  factory FilaBalance.fromJson(Map<String, dynamic> j) => FilaBalance(j['codigo'] as String, j['cuenta'] as String,
      j['tipo'] as String, _d(j['debe']), _d(j['haber']), _d(j['saldoDeudor']), _d(j['saldoAcreedor']));
}

class BalanceComprobacion {
  const BalanceComprobacion(this.filas, this.totalDebe, this.totalHaber, this.totalDeudor, this.totalAcreedor, this.cuadra);

  final List<FilaBalance> filas;
  final double totalDebe;
  final double totalHaber;
  final double totalDeudor;
  final double totalAcreedor;
  final bool cuadra;

  factory BalanceComprobacion.fromJson(Map<String, dynamic> j) => BalanceComprobacion(
        (j['filas'] as List).map((f) => FilaBalance.fromJson(f as Map<String, dynamic>)).toList(),
        _d(j['totalDebe']),
        _d(j['totalHaber']),
        _d(j['totalSaldoDeudor']),
        _d(j['totalSaldoAcreedor']),
        j['cuadra'] as bool,
      );
}

class Renglon {
  const Renglon(this.codigo, this.cuenta, this.monto);

  final String codigo;
  final String cuenta;
  final double monto;

  static List<Renglon> lista(Object? json) => (json as List)
      .map((r) => r as Map<String, dynamic>)
      .map((r) => Renglon(r['codigo'] as String, r['cuenta'] as String, _d(r['monto'])))
      .toList();
}

class EstadoResultados {
  const EstadoResultados({
    required this.ingresos,
    required this.totalIngresos,
    required this.costos,
    required this.totalCostos,
    required this.utilidadBruta,
    required this.gastos,
    required this.totalGastos,
    required this.utilidadNeta,
  });

  final List<Renglon> ingresos;
  final double totalIngresos;
  final List<Renglon> costos;
  final double totalCostos;
  final double utilidadBruta;
  final List<Renglon> gastos;
  final double totalGastos;
  final double utilidadNeta;

  factory EstadoResultados.fromJson(Map<String, dynamic> j) => EstadoResultados(
        ingresos: Renglon.lista(j['ingresos']),
        totalIngresos: _d(j['totalIngresos']),
        costos: Renglon.lista(j['costos']),
        totalCostos: _d(j['totalCostos']),
        utilidadBruta: _d(j['utilidadBruta']),
        gastos: Renglon.lista(j['gastos']),
        totalGastos: _d(j['totalGastos']),
        utilidadNeta: _d(j['utilidadNeta']),
      );
}

class BalanceGeneral {
  const BalanceGeneral({
    required this.activos,
    required this.totalActivos,
    required this.pasivos,
    required this.totalPasivos,
    required this.capital,
    required this.resultadoDelEjercicio,
    required this.totalCapital,
    required this.totalPasivoYCapital,
    required this.cuadra,
  });

  final List<Renglon> activos;
  final double totalActivos;
  final List<Renglon> pasivos;
  final double totalPasivos;
  final List<Renglon> capital;
  final double resultadoDelEjercicio;
  final double totalCapital;
  final double totalPasivoYCapital;
  final bool cuadra;

  factory BalanceGeneral.fromJson(Map<String, dynamic> j) => BalanceGeneral(
        activos: Renglon.lista(j['activos']),
        totalActivos: _d(j['totalActivos']),
        pasivos: Renglon.lista(j['pasivos']),
        totalPasivos: _d(j['totalPasivos']),
        capital: Renglon.lista(j['capital']),
        resultadoDelEjercicio: _d(j['resultadoDelEjercicio']),
        totalCapital: _d(j['totalCapital']),
        totalPasivoYCapital: _d(j['totalPasivoYCapital']),
        cuadra: j['cuadra'] as bool,
      );
}

// ---------- Panel ----------

class ProductoAlerta {
  const ProductoAlerta(this.id, this.codigo, this.nombre, this.stock, this.stockMinimo);

  final int id;
  final String codigo;
  final String nombre;
  final int stock;
  final int stockMinimo;
}

class Panel {
  const Panel({
    required this.ventasHoy,
    required this.cantidadVentasHoy,
    required this.ventasMes,
    required this.cantidadVentasMes,
    required this.utilidadBrutaMes,
    required this.comprasMes,
    required this.valorInventario,
    required this.ordenesPendientes,
    required this.bajoMinimo,
    required this.ventasSemana,
  });

  final double ventasHoy;
  final int cantidadVentasHoy;
  final double ventasMes;
  final int cantidadVentasMes;
  final double utilidadBrutaMes;
  final double comprasMes;
  final double valorInventario;
  final int ordenesPendientes;
  final List<ProductoAlerta> bajoMinimo;
  final List<(DateTime, double)> ventasSemana;

  factory Panel.fromJson(Map<String, dynamic> j) => Panel(
        ventasHoy: _d(j['ventasHoy']),
        cantidadVentasHoy: j['cantidadVentasHoy'] as int,
        ventasMes: _d(j['ventasMes']),
        cantidadVentasMes: j['cantidadVentasMes'] as int,
        utilidadBrutaMes: _d(j['utilidadBrutaMes']),
        comprasMes: _d(j['comprasMes']),
        valorInventario: _d(j['valorInventario']),
        ordenesPendientes: j['ordenesPendientes'] as int,
        bajoMinimo: (j['productosBajoMinimo'] as List)
            .map((p) => p as Map<String, dynamic>)
            .map((p) => ProductoAlerta(
                p['id'] as int, p['codigo'] as String, p['nombre'] as String, p['stock'] as int, p['stockMinimo'] as int))
            .toList(),
        ventasSemana: (j['ventasUltimos7Dias'] as List)
            .map((v) => v as Map<String, dynamic>)
            .map((v) => (leerDia(v['fecha'] as String), _d(v['total'])))
            .toList(),
      );
}

// ---------- Reporte de ventas ----------

class ResumenVentas {
  const ResumenVentas({
    required this.facturas,
    required this.unidades,
    required this.total,
    required this.baseImponible,
    required this.iva,
    required this.costo,
    required this.utilidadBruta,
    required this.margen,
    required this.ticketPromedio,
  });

  final int facturas;
  final int unidades;
  final double total;
  final double baseImponible;
  final double iva;
  final double costo;
  final double utilidadBruta;
  final double margen;
  final double ticketPromedio;

  factory ResumenVentas.fromJson(Map<String, dynamic> j) => ResumenVentas(
        facturas: j['facturas'] as int,
        unidades: j['unidades'] as int,
        total: _d(j['total']),
        baseImponible: _d(j['baseImponible']),
        iva: _d(j['iva']),
        costo: _d(j['costo']),
        utilidadBruta: _d(j['utilidadBruta']),
        margen: _d(j['margen']),
        ticketPromedio: _d(j['ticketPromedio']),
      );
}

/// Fila genérica de un desglose (producto, categoría, vendedor, cliente o forma de pago).
class FilaReporte {
  const FilaReporte({
    required this.titulo,
    this.detalle,
    this.cantidad = 0,
    this.facturas = 0,
    required this.total,
    this.utilidad,
    this.margen,
    required this.participacion,
  });

  final String titulo;
  final String? detalle;
  final int cantidad;
  final int facturas;
  final double total;
  final double? utilidad;
  final double? margen;

  /// Porcentaje del total del período.
  final double participacion;
}

/// Ventas de un departamento, con el producto más vendido ahí (mapa).
class VentaDepartamento {
  const VentaDepartamento(this.departamento, this.iso, this.facturas, this.unidades, this.total, this.participacion,
      this.productoTop, this.unidadesProductoTop);

  final String departamento;
  final String? iso;
  final int facturas;
  final int unidades;
  final double total;
  final double participacion;
  final String? productoTop;
  final int unidadesProductoTop;

  factory VentaDepartamento.fromJson(Map<String, dynamic> j) => VentaDepartamento(
        j['departamento'] as String,
        j['iso'] as String?,
        j['facturas'] as int,
        j['unidades'] as int,
        _d(j['total']),
        _d(j['participacion']),
        j['productoTop'] as String?,
        (j['unidadesProductoTop'] as int?) ?? 0,
      );
}

class VentaEstado {
  const VentaEstado(this.estado, this.nombre, this.facturas, this.total);

  final String estado;
  final String nombre;
  final int facturas;
  final double total;
}

class ReporteVentas {
  const ReporteVentas({
    required this.resumen,
    required this.anterior,
    required this.porDia,
    required this.porProducto,
    required this.porCategoria,
    required this.porVendedor,
    required this.porCliente,
    required this.porFormaPago,
    this.porDepartamento = const [],
    this.porEstado = const [],
  });

  final ResumenVentas resumen;
  final ResumenVentas anterior;
  final List<(DateTime, int, double)> porDia;
  final List<FilaReporte> porProducto;
  final List<FilaReporte> porCategoria;
  final List<FilaReporte> porVendedor;
  final List<FilaReporte> porCliente;
  final List<FilaReporte> porFormaPago;
  final List<VentaDepartamento> porDepartamento;
  final List<VentaEstado> porEstado;

  static List<FilaReporte> _filas(Object? json, FilaReporte Function(Map<String, dynamic>) de) =>
      (json as List).map((e) => de(e as Map<String, dynamic>)).toList();

  factory ReporteVentas.fromJson(Map<String, dynamic> j) => ReporteVentas(
        resumen: ResumenVentas.fromJson(j['resumen'] as Map<String, dynamic>),
        anterior: ResumenVentas.fromJson(j['periodoAnterior'] as Map<String, dynamic>),
        porDia: (j['porDia'] as List)
            .map((d) => d as Map<String, dynamic>)
            .map((d) => (leerDia(d['fecha'] as String), d['facturas'] as int, _d(d['total'])))
            .toList(),
        porProducto: _filas(
            j['porProducto'],
            (p) => FilaReporte(
                  titulo: p['nombre'] as String,
                  detalle: [p['codigo'] as String, if (p['categoria'] != null) p['categoria'] as String].join(' · '),
                  cantidad: p['unidades'] as int,
                  total: _d(p['total']),
                  utilidad: _d(p['utilidad']),
                  margen: _d(p['margen']),
                  participacion: _d(p['participacion']),
                )),
        porCategoria: _filas(
            j['porCategoria'],
            (c) => FilaReporte(
                  titulo: c['categoria'] as String,
                  cantidad: c['unidades'] as int,
                  total: _d(c['total']),
                  utilidad: _d(c['utilidad']),
                  participacion: _d(c['participacion']),
                )),
        porVendedor: _filas(
            j['porVendedor'],
            (v) => FilaReporte(
                  titulo: v['vendedor'] as String,
                  facturas: v['facturas'] as int,
                  total: _d(v['total']),
                  utilidad: _d(v['utilidad']),
                  participacion: _d(v['participacion']),
                )),
        porCliente: _filas(
            j['porCliente'],
            (c) => FilaReporte(
                  titulo: c['cliente'] as String,
                  detalle: 'NIT ${c['nit']}',
                  facturas: c['facturas'] as int,
                  total: _d(c['total']),
                  participacion: _d(c['participacion']),
                )),
        porFormaPago: _filas(
            j['porFormaPago'],
            (f) => FilaReporte(
                  titulo: formaPagoLegible(f['formaPago'] as String),
                  facturas: f['facturas'] as int,
                  total: _d(f['total']),
                  participacion: _d(f['participacion']),
                )),
        porDepartamento: ((j['porDepartamento'] as List?) ?? const [])
            .map((d) => VentaDepartamento.fromJson(d as Map<String, dynamic>))
            .toList(),
        porEstado: ((j['porEstado'] as List?) ?? const [])
            .map((e) => e as Map<String, dynamic>)
            .map((e) => VentaEstado(e['estado'] as String, e['nombre'] as String, e['facturas'] as int, _d(e['total'])))
            .toList(),
      );
}
