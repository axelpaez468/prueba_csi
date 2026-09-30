import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/network/api_exception.dart';
import '../../core/security/permisos.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_shell.dart';
import '../../data/models/usuario.dart';
import '../../data/repositories/usuario_repository.dart';
import '../auth/session_controller.dart';
import '../shell/app_top_bar.dart';
import 'usuario_form_dialog.dart';

/// Administración de usuarios (solo ADMIN; la API lo exige).
class UsuariosScreen extends StatefulWidget {
  const UsuariosScreen({super.key});

  @override
  State<UsuariosScreen> createState() => _UsuariosScreenState();
}

enum _Filtro { todos, activos, inactivos }

class _UsuariosScreenState extends State<UsuariosScreen> {
  final _buscar = TextEditingController();
  List<Usuario> _usuarios = const [];
  bool _cargando = true;
  String? _error;
  _Filtro _filtro = _Filtro.todos;

  UsuarioRepository get _repo => context.read<UsuarioRepository>();

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    _buscar.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final lista = await _repo.listar(buscar: _buscar.text);
      if (mounted) setState(() => _usuarios = lista);
    } on UnauthorizedException {
      // La app vuelve al login.
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  void _avisar(String mensaje) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(mensaje)));

  Future<void> _abrirFormulario([Usuario? usuario]) async {
    final guardado = await showDialog<Usuario>(context: context, builder: (_) => UsuarioFormDialog(usuario: usuario));
    if (guardado == null || !mounted) return;
    _avisar(usuario == null
        ? 'Usuario creado. Enviamos la invitación a ${guardado.email}.'
        : 'Cambios guardados para ${guardado.nombreCompleto}.');
    await _cargar();
  }

  Future<bool> _confirmar(String titulo, String mensaje, String accion, {bool peligrosa = false}) async =>
      await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(titulo),
          content: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 420), child: Text(mensaje)),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancelar')),
            FilledButton(
              style: peligrosa ? FilledButton.styleFrom(backgroundColor: AppColors.danger) : null,
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(accion),
            ),
          ],
        ),
      ) ??
      false;

  Future<void> _ejecutar(Future<void> Function() accion) async {
    try {
      await accion();
      await _cargar();
    } on ApiException catch (e) {
      _avisar(e.message); // p. ej. "tiene pedidos, desactívelo" o "debe quedar un administrador activo"
    }
  }

  Future<void> _accion(String accion, Usuario u) async {
    switch (accion) {
      case 'editar':
        await _abrirFormulario(u);
      case 'invitacion':
        await _ejecutar(() async => _avisar(await _repo.reenviarInvitacion(u.id)));
      case 'desactivar':
        if (await _confirmar('Desactivar usuario',
            '${u.nombreCompleto} perderá el acceso de inmediato (se cerrarán sus sesiones). Su historial de pedidos se conserva.',
            'Desactivar')) {
          await _ejecutar(() async => _repo.cambiarEstado(u.id, activo: false));
        }
      case 'activar':
        await _ejecutar(() async => _repo.cambiarEstado(u.id, activo: true));
      case 'eliminar':
        if (await _confirmar('Eliminar usuario',
            'Se eliminará a ${u.nombreCompleto} de forma permanente. Solo es posible si no tiene pedidos registrados.',
            'Eliminar',
            peligrosa: true)) {
          await _ejecutar(() async {
            await _repo.eliminar(u.id);
            _avisar('Usuario eliminado.');
          });
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    final compacto = Breakpoints.esCompacto(context);
    final margen = compacto ? 16.0 : 24.0;
    final miEmail = context.watch<SessionController>().session?.email;
    final visibles = _usuarios
        .where((u) => switch (_filtro) {
              _Filtro.todos => true,
              _Filtro.activos => u.activo,
              _Filtro.inactivos => !u.activo,
            })
        .toList();
    final activos = _usuarios.where((u) => u.activo).length;

    return Scaffold(
      appBar: AppTopBar(
        leading: IconButton(
          tooltip: 'Volver',
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const Icon(Icons.arrow_back),
        ),
      ),
      floatingActionButton: compacto
          ? FloatingActionButton(
              tooltip: 'Nuevo usuario',
              onPressed: () => _abrirFormulario(),
              child: const Icon(Icons.person_add_alt_1),
            )
          : null,
      body: RefreshIndicator(
        onRefresh: _cargar,
        child: ListView(
          padding: const EdgeInsets.only(bottom: 88),
          children: [
            PageBody(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  PageHeader(
                    titulo: 'Usuarios',
                    subtitulo: '${_usuarios.length} usuarios · $activos activos',
                    acciones: [
                      SizedBox(
                        width: 260,
                        child: TextField(
                          controller: _buscar,
                          onSubmitted: (_) => _cargar(),
                          decoration: const InputDecoration(
                            hintText: 'Buscar por nombre, correo o código',
                            prefixIcon: Icon(Icons.search),
                            isDense: true,
                          ),
                        ),
                      ),
                      if (!compacto)
                        FilledButton.icon(
                          onPressed: () => _abrirFormulario(),
                          icon: const Icon(Icons.person_add_alt_1, size: 18),
                          label: const Text('Nuevo usuario'),
                        ),
                    ],
                  ),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: margen),
                    child: SegmentedButton<_Filtro>(
                      segments: const [
                        ButtonSegment(value: _Filtro.todos, label: Text('Todos')),
                        ButtonSegment(value: _Filtro.activos, label: Text('Activos')),
                        ButtonSegment(value: _Filtro.inactivos, label: Text('Inactivos')),
                      ],
                      selected: {_filtro},
                      showSelectedIcon: false,
                      onSelectionChanged: (s) => setState(() => _filtro = s.first),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Padding(
                    padding: EdgeInsets.fromLTRB(margen, 0, margen, 24),
                    child: Card(
                      clipBehavior: Clip.antiAlias,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (_cargando) const LinearProgressIndicator(),
                          if (_error != null) Padding(padding: const EdgeInsets.all(16), child: InlineBanner.error(_error!)),
                          if (!_cargando && _error == null && visibles.isEmpty)
                            const EmptyState(icono: Icons.group_off_outlined, titulo: 'No hay usuarios que mostrar'),
                          LayoutBuilder(
                            builder: (context, constraints) {
                              final tabla = constraints.maxWidth >= 820;
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  if (tabla && visibles.isNotEmpty) const _EncabezadoTabla(),
                                  for (final (i, u) in visibles.indexed) ...[
                                    if (i > 0 || tabla) const Divider(),
                                    _FilaUsuario(
                                      usuario: u,
                                      tabla: tabla,
                                      esUnoMismo: u.email == miEmail,
                                      alElegir: (a) => _accion(a, u),
                                    ),
                                  ],
                                ],
                              );
                            },
                          ),
                        ],
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

TextStyle? _estiloEncabezado(BuildContext context) => Theme.of(context)
    .textTheme
    .labelMedium
    ?.copyWith(color: AppColors.textSecondary, letterSpacing: 0.4);

class _EncabezadoTabla extends StatelessWidget {
  const _EncabezadoTabla();

  @override
  Widget build(BuildContext context) {
    final e = _estiloEncabezado(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 12, 12),
      child: Row(children: [
        Expanded(flex: 4, child: Text('USUARIO', style: e)),
        Expanded(flex: 2, child: Text('CÓDIGO', style: e)),
        Expanded(flex: 2, child: Text('TELÉFONO', style: e)),
        Expanded(flex: 2, child: Text('ROL', style: e)),
        Expanded(flex: 2, child: Text('ESTADO', style: e)),
        const SizedBox(width: 48),
      ]),
    );
  }
}

class _FilaUsuario extends StatelessWidget {
  const _FilaUsuario({required this.usuario, required this.tabla, required this.esUnoMismo, required this.alElegir});

  final Usuario usuario;
  final bool tabla;
  final bool esUnoMismo;
  final ValueChanged<String> alElegir;

  @override
  Widget build(BuildContext context) {
    final u = usuario;
    final theme = Theme.of(context);
    final secundario = theme.textTheme.bodySmall?.copyWith(color: AppColors.textSecondary);

    final identidad = Row(children: [
      CircleAvatar(
        radius: 18,
        backgroundColor: u.activo ? AppColors.primary : AppColors.border,
        child: Text(u.iniciales,
            style: TextStyle(color: u.activo ? Colors.white : AppColors.textSecondary, fontWeight: FontWeight.w600, fontSize: 13)),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(esUnoMismo ? '${u.nombreCompleto} (tú)' : u.nombreCompleto,
              style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis),
          Text(u.email, style: secundario, overflow: TextOverflow.ellipsis),
        ]),
      ),
    ]);

    final rol = u.esAdmin
        ? const StatusPill(texto: 'Administrador', color: AppColors.primary, fondo: Color(0xFFE8EEF7))
        : StatusPill(texto: Roles.nombre(u.rol), color: AppColors.textSecondary, fondo: AppColors.background);
    final estado = !u.activo
        ? const StatusPill(texto: 'Inactivo', color: AppColors.danger, fondo: AppColors.dangerBg)
        : !u.tieneContrasena
            ? const StatusPill(texto: 'Invitación pendiente', color: AppColors.warning, fondo: AppColors.warningBg)
            : const StatusPill(texto: 'Activo', color: AppColors.success, fondo: AppColors.successBg);
    final menu = _MenuAcciones(usuario: u, esUnoMismo: esUnoMismo, alElegir: alElegir);

    if (tabla) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 10, 12, 10),
        child: Row(children: [
          Expanded(flex: 4, child: identidad),
          Expanded(flex: 2, child: Text(u.codigoCorporativo, style: theme.textTheme.bodyMedium)),
          Expanded(flex: 2, child: Text(u.telefonoFormateado, style: theme.textTheme.bodyMedium)),
          Expanded(flex: 2, child: Align(alignment: Alignment.centerLeft, child: rol)),
          Expanded(flex: 2, child: Align(alignment: Alignment.centerLeft, child: estado)),
          SizedBox(width: 48, child: menu),
        ]),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 4, 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [Expanded(child: identidad), menu]),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.only(left: 48),
          child: Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
            Text('${u.codigoCorporativo} · ${u.telefonoFormateado}', style: secundario),
            rol,
            estado,
          ]),
        ),
      ]),
    );
  }
}

class _MenuAcciones extends StatelessWidget {
  const _MenuAcciones({required this.usuario, required this.esUnoMismo, required this.alElegir});

  final Usuario usuario;
  final bool esUnoMismo;
  final ValueChanged<String> alElegir;

  PopupMenuItem<String> _item(String valor, IconData icono, String texto, {Color? color}) => PopupMenuItem(
        value: valor,
        child: Row(children: [
          Icon(icono, size: 18, color: color),
          const SizedBox(width: 10),
          Text(texto, style: TextStyle(color: color)),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final u = usuario;
    return PopupMenuButton<String>(
      tooltip: 'Acciones',
      icon: const Icon(Icons.more_vert),
      onSelected: alElegir,
      itemBuilder: (_) => [
        _item('editar', Icons.edit_outlined, 'Editar'),
        if (u.activo) _item('invitacion', Icons.forward_to_inbox_outlined,
            u.tieneContrasena ? 'Enviar enlace para nueva contraseña' : 'Reenviar invitación'),
        // Un administrador no puede desactivarse ni eliminarse a sí mismo (la API también lo impide).
        if (!esUnoMismo) ...[
          if (u.activo)
            _item('desactivar', Icons.block, 'Desactivar')
          else
            _item('activar', Icons.check_circle_outline, 'Activar'),
          const PopupMenuDivider(),
          _item('eliminar', Icons.delete_outline, 'Eliminar', color: AppColors.danger),
        ],
      ],
    );
  }
}
