import 'package:flutter/material.dart';

/// Etapas de una venta (espejo de backend/Domain/Pipeline.cs).
class EstadosVenta {
  const EstadosVenta._();

  static const nuevo = 'NUEVO';
  static const revisado = 'REVISADO';
  static const autorizado = 'AUTORIZADO';
  static const despachado = 'DESPACHADO';
  static const enCamino = 'EN_CAMINO';
  static const entregado = 'ENTREGADO';

  static const orden = [nuevo, revisado, autorizado, despachado, enCamino, entregado];

  static String nombre(String e) => switch (e) {
        nuevo => 'Nuevo',
        revisado => 'Revisado',
        autorizado => 'Autorizado',
        despachado => 'Despachado',
        enCamino => 'En camino',
        entregado => 'Entregado / cobrado',
        _ => e,
      };

  /// Verbo del botón que lleva a esta etapa.
  static String accion(String e) => switch (e) {
        revisado => 'Marcar revisado',
        autorizado => 'Autorizar',
        despachado => 'Despachar',
        enCamino => 'Enviar (en camino)',
        entregado => 'Confirmar entrega y cobro',
        _ => 'Avanzar',
      };

  static IconData icono(String e) => switch (e) {
        nuevo => Icons.fiber_new_outlined,
        revisado => Icons.fact_check_outlined,
        autorizado => Icons.verified_outlined,
        despachado => Icons.inventory_outlined,
        enCamino => Icons.local_shipping_outlined,
        _ => Icons.task_alt,
      };

  static Color color(String e) => switch (e) {
        nuevo => const Color(0xFF64748B),
        revisado => const Color(0xFF0EA5E9),
        autorizado => const Color(0xFF6366F1),
        despachado => const Color(0xFFF59E0B),
        enCamino => const Color(0xFFEA580C),
        _ => const Color(0xFF0E9F6E),
      };

  /// Quién mueve cada etapa (texto de ayuda).
  static String responsable(String e) => switch (e) {
        revisado => 'Vendedor',
        autorizado => 'Administración o contabilidad',
        despachado || enCamino || entregado => 'Bodega',
        _ => '',
      };
}

class HistorialEstado {
  const HistorialEstado(this.estado, this.fecha, this.usuario, this.nota);

  final String estado;
  final DateTime fecha;
  final String? usuario;
  final String? nota;

  factory HistorialEstado.fromJson(Map<String, dynamic> j) => HistorialEstado(
      j['estado'] as String, DateTime.parse(j['fecha'] as String), j['usuario'] as String?, j['nota'] as String?);
}

class TarjetaPipeline {
  const TarjetaPipeline({
    required this.numero,
    required this.fecha,
    required this.clienteNombre,
    required this.vendedor,
    required this.total,
    required this.productos,
    this.departamento,
    this.municipio,
    required this.estado,
    required this.estadoDesde,
    this.puedeAvanzarA,
  });

  final int numero;
  final DateTime fecha;
  final String clienteNombre;
  final String vendedor;
  final double total;
  final int productos;
  final String? departamento;
  final String? municipio;
  final String estado;
  final DateTime estadoDesde;

  /// Siguiente etapa si el usuario puede mover la venta; null si no le toca.
  final String? puedeAvanzarA;

  /// Días en la etapa actual (para resaltar las atrasadas).
  int get diasEnEtapa => DateTime.now().toUtc().difference(estadoDesde).inDays;

  factory TarjetaPipeline.fromJson(Map<String, dynamic> j) => TarjetaPipeline(
        numero: j['numero'] as int,
        fecha: DateTime.parse(j['fecha'] as String),
        clienteNombre: j['clienteNombre'] as String,
        vendedor: j['vendedor'] as String,
        total: (j['total'] as num).toDouble(),
        productos: j['productos'] as int,
        departamento: j['departamento'] as String?,
        municipio: j['municipio'] as String?,
        estado: j['estado'] as String,
        estadoDesde: DateTime.parse(j['estadoDesde'] as String),
        puedeAvanzarA: j['puedeAvanzarA'] as String?,
      );
}

class Departamento {
  const Departamento(this.nombre, this.iso, this.municipios);

  final String nombre;
  final String iso;
  final List<String> municipios;

  factory Departamento.fromJson(Map<String, dynamic> j) =>
      Departamento(j['nombre'] as String, j['iso'] as String, (j['municipios'] as List).cast<String>());
}
