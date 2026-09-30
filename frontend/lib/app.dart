import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';

import 'core/config/app_config.dart';
import 'core/network/api_client.dart';
import 'core/security/token_storage.dart';
import 'core/theme/app_theme.dart';
import 'data/repositories/auth_repository.dart';
import 'data/repositories/cuenta_repository.dart';
import 'data/repositories/pedido_repository.dart';
import 'data/repositories/producto_repository.dart';
import 'features/auth/login_screen.dart';
import 'features/auth/restablecer_password_screen.dart';
import 'features/auth/segundo_factor_screen.dart';
import 'features/auth/session_controller.dart';
import 'features/cart/cart_controller.dart';
import 'features/catalog/catalog_controller.dart';
import 'features/catalog/catalog_screen.dart';

/// Composición de dependencias: core -> data -> features.
class PedidosApp extends StatefulWidget {
  const PedidosApp({super.key});

  @override
  State<PedidosApp> createState() => _PedidosAppState();
}

class _PedidosAppState extends State<PedidosApp> {
  final _navigatorKey = GlobalKey<NavigatorState>();
  final _messengerKey = GlobalKey<ScaffoldMessengerState>();

  late final TokenStorage _storage;
  late final ApiClient _api;
  late final AuthRepository _authRepo;
  late final CuentaRepository _cuentaRepo;
  late final SessionController _session;
  late final CatalogController _catalogo;
  late final CartController _carrito;

  SessionStatus? _ultimoEstado;

  /// Token del enlace "restablecer contraseña" del correo (http://.../?restablecer=TOKEN).
  String? _tokenRestablecer = Uri.base.queryParameters['restablecer'];

  @override
  void initState() {
    super.initState();
    _storage = TokenStorage();
    _api = ApiClient(baseUrl: AppConfig.apiUrl, httpClient: http.Client(), tokenProvider: _storage.readToken);
    _authRepo = AuthRepository(_api);
    _cuentaRepo = CuentaRepository(_api);
    _session = SessionController(_authRepo, _storage);
    _catalogo = CatalogController(ProductoRepository(_api));
    _carrito = CartController(PedidoRepository(_api));

    // Cualquier 401 en una petición autenticada cierra la sesión.
    _api.onUnauthorized = () => _session.logout(expirada: true);
    _session.addListener(_alCambiarSesion);
    _session.restore();
  }

  /// Al salir (voluntariamente o por 401) se descartan pantallas y datos del usuario anterior.
  void _alCambiarSesion() {
    final estado = _session.status;
    if (estado == _ultimoEstado) return;
    _ultimoEstado = estado;

    if (estado == SessionStatus.unauthenticated) {
      _navigatorKey.currentState?.popUntil((r) => r.isFirst);
      _messengerKey.currentState?.clearSnackBars();
      _carrito.vaciar();
      _catalogo.limpiar();
    }
  }

  @override
  void dispose() {
    _session.removeListener(_alCambiarSesion);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider.value(value: _authRepo),
        Provider.value(value: _cuentaRepo),
        ChangeNotifierProvider.value(value: _session),
        ChangeNotifierProvider.value(value: _catalogo),
        ChangeNotifierProvider.value(value: _carrito),
      ],
      child: MaterialApp(
        title: 'Sistema de Pedidos',
        navigatorKey: _navigatorKey,
        scaffoldMessengerKey: _messengerKey,
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        home: Consumer<SessionController>(
          builder: (_, session, _) {
            final token = _tokenRestablecer;
            if (token != null && session.status != SessionStatus.authenticated) {
              return RestablecerPasswordScreen(token: token, alTerminar: () => setState(() => _tokenRestablecer = null));
            }
            return switch (session.status) {
              SessionStatus.restoring => const Scaffold(body: Center(child: CircularProgressIndicator())),
              SessionStatus.unauthenticated => const LoginScreen(),
              SessionStatus.segundoFactor => const SegundoFactorScreen(),
              SessionStatus.authenticated => const CatalogScreen(),
            };
          },
        ),
      ),
    );
  }
}
