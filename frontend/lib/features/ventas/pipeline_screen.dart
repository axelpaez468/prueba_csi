import 'dart:async';

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

/// Tablero tipo kanban de las ventas por etapa. Las tarjetas se arrastran a la siguiente etapa (o se usa el
/// botón de la tarjeta); solo se pueden mover las que le tocan al rol del usuario y solo una etapa hacia
/// adelante, igual que valida el backend. En celular se ve una etapa a la vez y se avanza con el botón.
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

  /// Ventas que ya se movieron en pantalla mientras el servidor confirma (número → etapa nueva).
  final Map<int, String> _movidas = {};

  /// Tarjeta que se está arrastrando (para resaltar la columna donde se puede soltar).
  TarjetaPipeline? _arrastrando;

  final _tablero = ScrollController();
  final _claveTablero = GlobalKey();
  Timer? _autoDesplazar;
  double _velocidad = 0;

  PipelineRepository get _repo => context.read<PipelineRepository>();

  @override
  Future<List<TarjetaPipeline>> obtener() => _repo.tablero();

  @override
  void dispose() {
    _buscar.dispose();
    _tablero.dispose();
    _autoDesplazar?.cancel();
    super.dispose();
  }

  String _estadoDe(TarjetaPipeline t) => _movidas[t.numero] ?? t.estado;

  Future<void> _avanzar(TarjetaPipeline t) async {
    final destino = t.puedeAvanzarA;
    if (destino == null || _avanzando.contains(t.numero)) return;
    final nota = await pedirNotaAvance(context, t.numero, destino);
    if (nota == null || !mounted) return;
    setState(() {
      _avanzando.add(t.numero);
      _movidas[t.numero] = destino;
    });
    try {
      final mensaje = await _repo.avanzar(t.numero, nota: nota.isEmpty ? null : nota);
      if (mounted) avisar(context, mensaje);
      await recargar();
    } on ApiException catch (e) {
      if (mounted) avisar(context, e.message);
    } finally {
      if (mounted) {
        setState(() {
          _avanzando.remove(t.numero);
          _movidas.remove(t.numero);
        });
      }
    }
  }

  void _abrir(TarjetaPipeline t) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => VentaDetalleScreen(numero: t.numero)));
    if (mounted) await recargar();
  }

  void _inicioArrastre(TarjetaPipeline t) => setState(() => _arrastrando = t);

  void _finArrastre() {
    _velocidad = 0;
    _autoDesplazar?.cancel();
    _autoDesplazar = null;
    if (mounted) setState(() => _arrastrando = null);
  }

  /// Si el puntero se acerca a un borde del tablero mientras arrastra, el tablero se desplaza solo.
  void _alMoverArrastre(DragUpdateDetails d) {
    final caja = _claveTablero.currentContext?.findRenderObject() as RenderBox?;
    if (caja == null || !_tablero.hasClients) return;
    const margen = 80.0;
    final x = caja.globalToLocal(d.globalPosition).dx;
    final ancho = caja.size.width;
    _velocidad = x < margen
        ? -(margen - x) / margen * 18
        : x > ancho - margen
            ? (x - (ancho - margen)) / margen * 18
            : 0;
    if (_velocidad == 0 || _autoDesplazar != null) return;
    _autoDesplazar = Timer.periodic(const Duration(milliseconds: 16), (timer) {
      if (_velocidad == 0 || !_tablero.hasClients) {
        timer.cancel();
        _autoDesplazar = null;
        return;
      }
      final p = _tablero.position;
      _tablero.jumpTo((p.pixels + _velocidad).clamp(p.minScrollExtent, p.maxScrollExtent));
    });
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
    final porEtapa = {for (final e in EstadosVenta.orden) e: tarjetas.where((t) => _estadoDe(t) == e).toList()};
    final pendientesMias = (datos ?? const <TarjetaPipeline>[]).where((t) => t.puedeAvanzarA != null).length;
    final ancho = MediaQuery.sizeOf(context).width;
    final kanban = ancho >= 900;
    // En pantallas táctiles el arrastre empieza con una pulsación larga para no estorbar el desplazamiento.
    final tactil = switch (Theme.of(context).platform) {
      TargetPlatform.android || TargetPlatform.iOS => true,
      _ => false,
    };

    return ModuloPage(
      titulo: 'Pipeline de ventas',
      subtitulo: '${tarjetas.length} ventas en el tablero · $pendientesMias esperan una acción tuya'
          '${kanban ? ' · ${tactil ? 'Mantén presionada' : 'Arrastra'} una tarjeta para pasarla a la siguiente etapa' : ''}',
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
            key: _claveTablero,
            height: (MediaQuery.sizeOf(context).height - 260).clamp(420.0, 900.0),
            // Columnas de al menos 250 px: si las 6 no caben, el tablero se desplaza horizontalmente.
            child: LayoutBuilder(builder: (context, c) {
              const separacion = 12.0;
              final columna = ((c.maxWidth - separacion * 5) / 6).clamp(250.0, 400.0);
              return ListView.separated(
                controller: _tablero,
                scrollDirection: Axis.horizontal,
                itemCount: EstadosVenta.orden.length,
                separatorBuilder: (_, _) => const SizedBox(width: separacion),
                itemBuilder: (_, i) {
                  final e = EstadosVenta.orden[i];
                  return SizedBox(
                    width: columna,
                    child: _Columna(
                      etapa: e,
                      tarjetas: porEtapa[e]!,
                      ancho: columna,
                      tactil: tactil,
                      arrastrando: _arrastrando,
                      avanzando: _avanzando,
                      movidas: _movidas,
                      alAvanzar: _avanzar,
                      alAbrir: _abrir,
                      alIniciarArrastre: _inicioArrastre,
                      alMoverArrastre: _alMoverArrastre,
                      alTerminarArrastre: _finArrastre,
                    ),
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
            _TarjetaVenta(
              tarjeta: t,
              avanzando: _avanzando.contains(t.numero),
              movida: _movidas.containsKey(t.numero),
              alAvanzar: _avanzar,
              alAbrir: _abrir,
            ),
        ],
      ],
    );
  }
}

class _Columna extends StatelessWidget {
  const _Columna({
    required this.etapa,
    required this.tarjetas,
    required this.ancho,
    required this.tactil,
    required this.arrastrando,
    required this.avanzando,
    required this.movidas,
    required this.alAvanzar,
    required this.alAbrir,
    required this.alIniciarArrastre,
    required this.alMoverArrastre,
    required this.alTerminarArrastre,
  });

  final String etapa;
  final List<TarjetaPipeline> tarjetas;
  final double ancho;
  final bool tactil;
  final TarjetaPipeline? arrastrando;
  final Set<int> avanzando;
  final Map<int, String> movidas;
  final ValueChanged<TarjetaPipeline> alAvanzar;
  final ValueChanged<TarjetaPipeline> alAbrir;
  final ValueChanged<TarjetaPipeline> alIniciarArrastre;
  final ValueChanged<DragUpdateDetails> alMoverArrastre;
  final VoidCallback alTerminarArrastre;

  @override
  Widget build(BuildContext context) {
    final color = EstadosVenta.color(etapa);
    final total = tarjetas.fold<double>(0, (s, t) => s + t.total);
    final destinoValido = arrastrando != null && arrastrando!.puedeAvanzarA == etapa;
    final origen = arrastrando != null && arrastrando!.estado == etapa;
    final apagada = arrastrando != null && !destinoValido && !origen;

    return DragTarget<TarjetaPipeline>(
      onWillAcceptWithDetails: (d) => d.data.puedeAvanzarA == etapa,
      onAcceptWithDetails: (d) => alAvanzar(d.data),
      builder: (context, encima, rechazadas) {
        final resaltada = encima.isNotEmpty;
        final rechazo = rechazadas.isNotEmpty && !origen;
        final borde = rechazo ? AppColors.danger : color;
        return AnimatedOpacity(
          duration: const Duration(milliseconds: 150),
          opacity: apagada && !rechazo ? 0.55 : 1,
          // Sin AnimatedContainer: interpolar un borde de un solo lado con uno completo rompe el radio de las esquinas.
          child: Container(
            decoration: BoxDecoration(
              color: resaltada
                  ? Color.alphaBlend(color.withValues(alpha: 0.16), const Color(0xFFE9EEF5))
                  : destinoValido
                      ? Color.alphaBlend(color.withValues(alpha: 0.07), const Color(0xFFE9EEF5))
                      : const Color(0xFFE9EEF5),
              borderRadius: BorderRadius.circular(16),
              border: destinoValido || rechazo
                  ? Border(
                      top: BorderSide(color: borde, width: 4),
                      left: BorderSide(color: borde, width: 2),
                      right: BorderSide(color: borde, width: 2),
                      bottom: BorderSide(color: borde, width: 2),
                    )
                  : Border(top: BorderSide(color: color, width: 4)),
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
              if (destinoValido)
                _AvisoSoltar(
                  key: const Key('zona-soltar'),
                  icono: Icons.file_download_outlined,
                  texto: 'Suelta aquí para "${EstadosVenta.accion(etapa)}"',
                  color: color,
                  fuerte: resaltada,
                ),
              if (rechazo)
                _AvisoSoltar(
                  icono: Icons.block,
                  texto: arrastrando?.puedeAvanzarA == null
                      ? 'No puedes mover esta venta'
                      : 'Solo puede pasar a "${EstadosVenta.nombre(arrastrando!.puedeAvanzarA!)}"',
                  color: AppColors.danger,
                  fuerte: true,
                ),
              Expanded(
                child: tarjetas.isEmpty
                    ? Center(child: textoSecundario(context, 'Sin ventas'))
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                        itemCount: tarjetas.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (_, i) => _TarjetaArrastrable(
                          tarjeta: tarjetas[i],
                          ancho: ancho - 16,
                          tactil: tactil,
                          avanzando: avanzando.contains(tarjetas[i].numero),
                          movida: movidas.containsKey(tarjetas[i].numero),
                          alAvanzar: alAvanzar,
                          alAbrir: alAbrir,
                          alIniciarArrastre: alIniciarArrastre,
                          alMoverArrastre: alMoverArrastre,
                          alTerminarArrastre: alTerminarArrastre,
                        ),
                      ),
              ),
            ]),
          ),
        );
      },
    );
  }
}

class _AvisoSoltar extends StatelessWidget {
  const _AvisoSoltar({super.key, required this.icono, required this.texto, required this.color, required this.fuerte});

  final IconData icono;
  final String texto;
  final Color color;
  final bool fuerte;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(8, 0, 8, 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: fuerte ? 0.18 : 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.6)),
      ),
      child: Row(children: [
        Icon(icono, size: 18, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Text(texto,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: color, fontSize: 12.5, fontWeight: FontWeight.w600)),
        ),
      ]),
    );
  }
}

/// Tarjeta del kanban: si el usuario puede moverla, se arrastra (con el mouse de inmediato; en pantallas
/// táctiles con pulsación larga). Si no, es una tarjeta normal.
class _TarjetaArrastrable extends StatelessWidget {
  const _TarjetaArrastrable({
    required this.tarjeta,
    required this.ancho,
    required this.tactil,
    required this.avanzando,
    required this.movida,
    required this.alAvanzar,
    required this.alAbrir,
    required this.alIniciarArrastre,
    required this.alMoverArrastre,
    required this.alTerminarArrastre,
  });

  final TarjetaPipeline tarjeta;
  final double ancho;
  final bool tactil;
  final bool avanzando;
  final bool movida;
  final ValueChanged<TarjetaPipeline> alAvanzar;
  final ValueChanged<TarjetaPipeline> alAbrir;
  final ValueChanged<TarjetaPipeline> alIniciarArrastre;
  final ValueChanged<DragUpdateDetails> alMoverArrastre;
  final VoidCallback alTerminarArrastre;

  @override
  Widget build(BuildContext context) {
    final tarjetaVisible = _TarjetaVenta(
      tarjeta: tarjeta,
      avanzando: avanzando,
      movida: movida,
      alAvanzar: alAvanzar,
      alAbrir: alAbrir,
      arrastrable: !tactil,
    );
    if (tarjeta.puedeAvanzarA == null || avanzando || movida) return tarjetaVisible;

    final flotante = SizedBox(
      width: ancho,
      child: Transform.rotate(
        angle: 0.035,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            boxShadow: const [BoxShadow(color: Color(0x330B1426), blurRadius: 24, offset: Offset(0, 12))],
          ),
          // Material transparente: la tarjeta flota en el Overlay, fuera del Scaffold.
          child: Material(type: MaterialType.transparency, child: tarjetaVisible),
        ),
      ),
    );
    final enSuLugar = Opacity(opacity: 0.35, child: tarjetaVisible);
    final contenido = MouseRegion(cursor: SystemMouseCursors.grab, child: tarjetaVisible);

    return tactil
        ? LongPressDraggable<TarjetaPipeline>(
            data: tarjeta,
            feedback: flotante,
            childWhenDragging: enSuLugar,
            onDragStarted: () => alIniciarArrastre(tarjeta),
            onDragUpdate: alMoverArrastre,
            onDragEnd: (_) => alTerminarArrastre(),
            child: contenido,
          )
        : Draggable<TarjetaPipeline>(
            data: tarjeta,
            feedback: flotante,
            childWhenDragging: enSuLugar,
            onDragStarted: () => alIniciarArrastre(tarjeta),
            onDragUpdate: alMoverArrastre,
            onDragEnd: (_) => alTerminarArrastre(),
            child: contenido,
          );
  }
}

class _TarjetaVenta extends StatelessWidget {
  const _TarjetaVenta({
    required this.tarjeta,
    required this.avanzando,
    required this.alAvanzar,
    required this.alAbrir,
    this.movida = false,
    this.arrastrable = false,
  });

  final TarjetaPipeline tarjeta;
  final bool avanzando;

  /// Ya se movió en pantalla y el servidor está confirmando el cambio.
  final bool movida;

  /// Muestra el ícono de "arrastrar" (solo en el kanban con mouse).
  final bool arrastrable;
  final ValueChanged<TarjetaPipeline> alAvanzar;
  final ValueChanged<TarjetaPipeline> alAbrir;

  @override
  Widget build(BuildContext context) {
    final t = tarjeta;
    final theme = Theme.of(context);
    final atrasada = !movida && t.estado != EstadosVenta.entregado && t.diasEnEtapa >= 2;
    final movible = t.puedeAvanzarA != null && !movida;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => alAbrir(t),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              if (arrastrable && movible)
                const Padding(
                  padding: EdgeInsets.only(right: 4),
                  child: Icon(Icons.drag_indicator, size: 16, color: AppColors.textSecondary),
                ),
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
            if (movida) ...[
              const SizedBox(height: 10),
              Row(children: [
                const SizedBox.square(dimension: 14, child: CircularProgressIndicator(strokeWidth: 2)),
                const SizedBox(width: 8),
                textoSecundario(context, 'Guardando…'),
              ]),
            ] else if (t.puedeAvanzarA != null) ...[
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
