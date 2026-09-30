import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/network/api_exception.dart';
import '../../core/widgets/app_shell.dart';
import '../../data/models/seguridad.dart';
import '../../data/repositories/cuenta_repository.dart';
import '../shell/app_top_bar.dart';
import 'seguridad_screen.dart';

/// Bitácora de accesos y eventos de seguridad de todos los usuarios (solo ADMIN; la API lo exige).
class BitacoraScreen extends StatefulWidget {
  const BitacoraScreen({super.key});

  @override
  State<BitacoraScreen> createState() => _BitacoraScreenState();
}

class _BitacoraScreenState extends State<BitacoraScreen> {
  final _filtro = TextEditingController();
  List<RegistroAcceso> _registros = const [];
  bool _cargando = true;
  String? _error;
  bool _soloFallidos = false;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    _filtro.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final r = await context.read<CuentaRepository>().bitacora(email: _filtro.text);
      if (mounted) setState(() => _registros = r);
    } on UnauthorizedException {
      // La app vuelve al login.
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final margen = Breakpoints.esCompacto(context) ? 16.0 : 24.0;
    final visibles = _soloFallidos ? _registros.where((r) => !r.exito).toList() : _registros;

    return Scaffold(
      appBar: AppTopBar(
        leading: IconButton(
          tooltip: 'Volver',
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const Icon(Icons.arrow_back),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _cargar,
        child: ListView(
          children: [
            PageBody(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  PageHeader(
                    titulo: 'Bitácora de accesos',
                    subtitulo: 'Últimos 100 eventos de seguridad de todos los usuarios',
                    acciones: [
                      SizedBox(
                        width: 280,
                        child: TextField(
                          controller: _filtro,
                          onSubmitted: (_) => _cargar(),
                          decoration: const InputDecoration(
                            hintText: 'Filtrar por correo',
                            prefixIcon: Icon(Icons.search),
                            isDense: true,
                          ),
                        ),
                      ),
                      IconButton.outlined(tooltip: 'Actualizar', onPressed: _cargando ? null : _cargar, icon: const Icon(Icons.refresh)),
                    ],
                  ),
                  Padding(
                    padding: EdgeInsets.fromLTRB(margen, 0, margen, 32),
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            SwitchListTile(
                              value: _soloFallidos,
                              onChanged: (v) => setState(() => _soloFallidos = v),
                              title: const Text('Mostrar solo intentos fallidos'),
                              contentPadding: EdgeInsets.zero,
                            ),
                            const Divider(),
                            if (_cargando) const LinearProgressIndicator(),
                            if (_error != null) Padding(padding: const EdgeInsets.all(12), child: InlineBanner.error(_error!)),
                            if (!_cargando && visibles.isEmpty && _error == null)
                              const Padding(padding: EdgeInsets.all(24), child: Center(child: Text('Sin eventos.'))),
                            for (final r in visibles) FilaAcceso(acceso: r, mostrarEmail: true),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
