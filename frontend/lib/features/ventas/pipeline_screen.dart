import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/network/api_exception.dart';
import '../../core/theme/app_theme.dart';
import '../../core/util/formatters.dart';
import '../../core/widgets/app_shell.dart';
import '../../core/widgets/erp_widgets.dart';
import '../../data/models/pipeline.dart';
import '../../data/repositories/erp_repositories.dart';
import '../shell/modulo_page.dart';
import 'pipeline_widgets.dart';
import 'ventas_screen.dart';

/// Tablero tipo kanban de las ventas por etapa. Cada tarjeta muestra el botón para pasar a la siguiente etapa
/// solo si al rol del usuario le toca darlo. En celular se ve una etapa a la vez.
class PipelineScreen extends StatefulWidget {
  const PipelineScreen({super.key});

  @override
  State<PipelineScreen> createState() => _PipelineScreenState();
}

class _PipelineScreenState extends State<PipelineScreen> with CargaDatos<PipelineScreen, List<TarjetaPipeline>> {
  final _buscar = TextEditingController();
  bool _soloMios = false;
  String _etapaMovil = EstadosVenta.nuevo;
  final Set<int> _avanzando = {};

  PipelineRepository get _repo => context.read<PipelineRepository>();

  @override
  Future<List<TarjetaPipeline>> obtener() => _repo.tablero();

  @override
  void dispose() {
    _buscar.dispose();
    super.dispose();
  }

  Future<void> _avanzar(TarjetaPipeline t) async {
    final destino = t.puedeAvanzarA!;
    final nota = await pedirNotaAvance(context, t.numero, destino);
    if (nota == null || !mounted) return;
    setState(() => _avanzando.add(t.numero));
    try {
      final mensaje = await _repo.avanzar(t.numero, nota: nota.isEmpty ? null : nota);
      if (mounted) avisar(context, mensaje);
      await recargar();
    } on ApiException catch (e) {
      if (mounted) avisar(context, e.message);
    } finally {
      if (mounted) setState(() => _avanzando.remove(t.numero));
    }
  }

  void _abrir(TarjetaPipeline t) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => VentaDetalleScreen(numero: t.numero)));
    if (mounted) await recargar();
  }

  @override
  Widget build(BuildContext context) {
    final texto = _buscar.text.trim().toLowerCase();
    final tarjetas = (datos ?? const <TarjetaPipeline>[])
        .where((t) => !_soloMios || t.puedeAvanzarA != null)
        .where((t) =>
            texto.isEmpty ||
            t.clienteNombre.toLowerCase().contains(texto) ||
            'a-${t.numero}'.contains(texto) ||
            (t.departamento?.toLowerCase().contains(texto) ?? false))
        .toList();
    final porEtapa = {for (final e in EstadosVenta.orden) e: tarjetas.where((t) => t.estado == e).toList()};
    final pendientesMias = (datos ?? const <TarjetaPipeline>[]).where((t) => t.puedeAvanzarA != null).length;
    final ancho = MediaQuery.sizeOf(context).width;
    final kanban = ancho >= 900;

    return ModuloPage(
      titulo: 'Pipeline de ventas',
      subtitulo: '${tarjetas.length} ventas en el tablero · $pendientesMias esperan una acción tuya',
      maxWidth: 1600,
      alRefrescar: recargar,
      acciones: [
        SizedBox(
          width: 260,
          child: TextField(
            controller: _buscar,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(hintText: 'Cliente, factura o departamento', prefixIcon: Icon(Icons.search), isDense: true),
          ),
        ),
        FilterChip(
          label: const Text('Me toca a mí'),
          selected: _soloMios,
          onSelected: (v) => setState(() => _soloMios = v),
        ),
      ],
      children: [
        if (cargando && datos == null) const LinearProgressIndicator(),
        if (error != null) InlineBanner.error(error!),
        if (datos != null && kanban)
          SizedBox(
            height: (MediaQuery.sizeOf(context).height - 260).clamp(420.0, 900.0),
            // Columnas de al menos 250 px: si las 6 no caben, el tablero se desplaza horizontalmente.
            child: LayoutBuilder(builder: (context, c) {
              const separacion = 12.0;
              final columna = ((c.maxWidth - separacion * 5) / 6).clamp(250.0, 400.0);
              return ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: EstadosVenta.orden.length,
                separatorBuilder: (_, _) => const SizedBox(width: separacion),
                itemBuilder: (_, i) {
                  final e = EstadosVenta.orden[i];
                  return SizedBox(
                    width: columna,
                    child: _Columna(etapa: e, tarjetas: porEtapa[e]!, avanzando: _avanzando, alAvanzar: _avanzar, alAbrir: _abrir),
                  );
                },
              );
            }),
          ),
        if (datos != null && !kanban) ...[
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              for (final e in EstadosVenta.orden)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    avatar: Icon(EstadosVenta.icono(e), size: 16, color: EstadosVenta.color(e)),
                    label: Text('${EstadosVenta.nombre(e)} (${porEtapa[e]!.length})'),
                    selected: _etapaMovil == e,
                    onSelected: (_) => setState(() => _etapaMovil = e),
                  ),
                ),
            ]),
          ),
          if (porEtapa[_etapaMovil]!.isEmpty)
            const Card(child: EmptyState(icono: Icons.inbox_outlined, titulo: 'No hay ventas en esta etapa')),
          for (final t in porEtapa[_etapaMovil]!)
            _TarjetaVenta(tarjeta: t, avanzando: _avanzando.contains(t.numero), alAvanzar: _avanzar, alAbrir: _abrir),
        ],
      ],
    );
  }
}

class _Columna extends StatelessWidget {
  const _Columna({required this.etapa, required this.tarjetas, required this.avanzando, required this.alAvanzar, required this.alAbrir});

  final String etapa;
  final List<TarjetaPipeline> tarjetas;
  final Set<int> avanzando;
  final ValueChanged<TarjetaPipeline> alAvanzar;
  final ValueChanged<TarjetaPipeline> alAbrir;

  @override
  Widget build(BuildContext context) {
    final color = EstadosVenta.color(etapa);
    final total = tarjetas.fold<double>(0, (s, t) => s + t.total);
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFE9EEF5),
        borderRadius: BorderRadius.circular(16),
        border: Border(top: BorderSide(color: color, width: 4)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(EstadosVenta.icono(etapa), size: 18, color: color),
              const SizedBox(width: 6),
              Expanded(child: textoFuerte(context, EstadosVenta.nombre(etapa), lineas: 1)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(99)),
                child: Text('${tarjetas.length}', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
              ),
            ]),
            textoSecundario(context, formatearMoneda(total)),
          ]),
        ),
        Expanded(
          child: tarjetas.isEmpty
              ? Center(child: textoSecundario(context, 'Sin ventas'))
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                  itemCount: tarjetas.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (_, i) => _TarjetaVenta(
                    tarjeta: tarjetas[i],
                    avanzando: avanzando.contains(tarjetas[i].numero),
                    alAvanzar: alAvanzar,
                    alAbrir: alAbrir,
                    compacta: true,
                  ),
                ),
        ),
      ]),
    );
  }
}

class _TarjetaVenta extends StatelessWidget {
  const _TarjetaVenta({
    required this.tarjeta,
    required this.avanzando,
    required this.alAvanzar,
    required this.alAbrir,
    this.compacta = false,
  });

  final TarjetaPipeline tarjeta;
  final bool avanzando;
  final ValueChanged<TarjetaPipeline> alAvanzar;
  final ValueChanged<TarjetaPipeline> alAbrir;
  final bool compacta;

  @override
  Widget build(BuildContext context) {
    final t = tarjeta;
    final theme = Theme.of(context);
    final atrasada = t.estado != EstadosVenta.entregado && t.diasEnEtapa >= 2;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => alAbrir(t),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(child: Text('A-${t.numero}', style: theme.textTheme.labelLarge?.copyWith(color: AppColors.primary))),
              Text(formatearMoneda(t.total), style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
            ]),
            const SizedBox(height: 4),
            textoFuerte(context, t.clienteNombre, lineas: 1),
            if (t.departamento != null)
              Row(children: [
                const Icon(Icons.place_outlined, size: 14, color: AppColors.textSecondary),
                const SizedBox(width: 4),
                Expanded(child: textoSecundario(context, '${t.municipio}, ${t.departamento}', lineas: 1)),
              ]),
            const SizedBox(height: 6),
            Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
              textoSecundario(context, '${t.vendedor} · ${t.productos} prod.'),
              if (atrasada)
                StatusPill(
                    texto: '${t.diasEnEtapa} días aquí', color: AppColors.danger, fondo: AppColors.dangerBg, icono: Icons.schedule),
            ]),
            if (t.puedeAvanzarA != null) ...[
              const SizedBox(height: 10),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: EstadosVenta.color(t.puedeAvanzarA!),
                  minimumSize: const Size.fromHeight(36),
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                ),
                onPressed: avanzando ? null : () => alAvanzar(t),
                icon: avanzando
                    ? const SizedBox.square(dimension: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : Icon(EstadosVenta.icono(t.puedeAvanzarA!), size: 16),
                label: Text(EstadosVenta.accion(t.puedeAvanzarA!), overflow: TextOverflow.ellipsis),
              ),
            ],
          ]),
        ),
      ),
    );
  }
}
