double _d(Object? v) => (v as num).toDouble();

/// Una etapa del pipeline en el pronóstico: total de sus ventas y lo que se espera cerrar (total × probabilidad).
class EtapaPronostico {
  const EtapaPronostico(this.estado, this.nombre, this.probabilidad, this.facturas, this.total, this.ponderado);

  final String estado;
  final String nombre;

  /// 0 a 100.
  final double probabilidad;
  final int facturas;
  final double total;
  final double ponderado;

  factory EtapaPronostico.fromJson(Map<String, dynamic> j) => EtapaPronostico(j['estado'] as String, j['nombre'] as String,
      _d(j['probabilidad']), j['facturas'] as int, _d(j['total']), _d(j['ponderado']));
}

class TramoPronostico {
  const TramoPronostico(this.desde, this.hasta, this.cerrado, this.abierto, this.ponderado);

  final DateTime desde;
  final DateTime hasta;
  final double cerrado;
  final double abierto;
  final double ponderado;

  factory TramoPronostico.fromJson(Map<String, dynamic> j) => TramoPronostico(DateTime.parse(j['desde'] as String),
      DateTime.parse(j['hasta'] as String), _d(j['cerrado']), _d(j['abierto']), _d(j['ponderado']));
}

class PronosticoVendedor {
  const PronosticoVendedor(this.vendedor, this.facturas, this.cerrado, this.abierto, this.ponderado, this.pronostico);

  final String vendedor;
  final int facturas;
  final double cerrado;
  final double abierto;
  final double ponderado;
  final double pronostico;

  factory PronosticoVendedor.fromJson(Map<String, dynamic> j) => PronosticoVendedor(j['vendedor'] as String,
      j['facturas'] as int, _d(j['cerrado']), _d(j['abierto']), _d(j['ponderado']), _d(j['pronostico']));
}

/// Pronóstico de ventas (forecast): lo cerrado más lo esperado de cada etapa abierta.
class Pronostico {
  const Pronostico({
    required this.agrupacion,
    required this.facturasCerradas,
    required this.cerrado,
    required this.facturasAbiertas,
    required this.abierto,
    required this.ponderadoAbierto,
    required this.pronostico,
    required this.probabilidadAbiertas,
    required this.avanceCierre,
    required this.etapas,
    required this.tendencia,
    required this.porVendedor,
    this.actualizadoEn,
    this.actualizadoPor,
  });

  /// DIA, SEMANA o MES.
  final String agrupacion;
  final int facturasCerradas;
  final double cerrado;
  final int facturasAbiertas;
  final double abierto;
  final double ponderadoAbierto;
  final double pronostico;
  final double probabilidadAbiertas;
  final double avanceCierre;
  final List<EtapaPronostico> etapas;
  final List<TramoPronostico> tendencia;
  final List<PronosticoVendedor> porVendedor;

  /// Última vez que se cambiaron las probabilidades (null: valores iniciales).
  final DateTime? actualizadoEn;
  final String? actualizadoPor;

  factory Pronostico.fromJson(Map<String, dynamic> j) => Pronostico(
        agrupacion: j['agrupacion'] as String,
        facturasCerradas: j['facturasCerradas'] as int,
        cerrado: _d(j['cerrado']),
        facturasAbiertas: j['facturasAbiertas'] as int,
        abierto: _d(j['abierto']),
        ponderadoAbierto: _d(j['ponderadoAbierto']),
        pronostico: _d(j['pronostico']),
        probabilidadAbiertas: _d(j['probabilidadAbiertas']),
        avanceCierre: _d(j['avanceCierre']),
        etapas: [for (final e in j['etapas'] as List) EtapaPronostico.fromJson(e as Map<String, dynamic>)],
        tendencia: [for (final t in j['tendencia'] as List) TramoPronostico.fromJson(t as Map<String, dynamic>)],
        porVendedor: [for (final v in j['porVendedor'] as List) PronosticoVendedor.fromJson(v as Map<String, dynamic>)],
        actualizadoEn: j['probabilidadesActualizadasEn'] == null ? null : DateTime.parse(j['probabilidadesActualizadasEn'] as String),
        actualizadoPor: j['probabilidadesActualizadasPor'] as String?,
      );
}
