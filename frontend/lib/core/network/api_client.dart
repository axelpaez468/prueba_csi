import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'api_exception.dart';

typedef TokenProvider = Future<String?> Function();

/// Cliente HTTP único de la app: agrega el Bearer token, traduce errores a [ApiException]
/// y avisa por [onUnauthorized] cuando el servidor responde 401 a una petición autenticada.
class ApiClient {
  ApiClient({
    required String baseUrl,
    required http.Client httpClient,
    required this.tokenProvider,
    this.timeout = const Duration(seconds: 15),
  })  : _baseUri = Uri.parse(baseUrl),
        _http = httpClient;

  final Uri _baseUri;
  final http.Client _http;
  final TokenProvider tokenProvider;
  final Duration timeout;

  /// Se asigna al componer la app (cierra la sesión y vuelve al login).
  void Function()? onUnauthorized;

  Future<dynamic> get(String path) => _send('GET', path);

  Future<dynamic> post(String path, Object body, {bool authenticated = true}) =>
      _send('POST', path, body: body, authenticated: authenticated);

  Future<dynamic> put(String path, Object body) => _send('PUT', path, body: body);

  Future<dynamic> delete(String path) => _send('DELETE', path);

  Future<dynamic> _send(String method, String path, {Object? body, bool authenticated = true}) async {
    final request = http.Request(method, _baseUri.resolve(path))
      ..headers['Accept'] = 'application/json';

    if (body != null) {
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode(body);
    }
    if (authenticated) {
      final token = await tokenProvider();
      if (token != null) request.headers['Authorization'] = 'Bearer $token';
    }

    final http.Response response;
    try {
      response = await http.Response.fromStream(await _http.send(request).timeout(timeout));
    } on TimeoutException {
      throw const ApiException('El servidor tardó demasiado en responder. Intente de nuevo.');
    } on http.ClientException {
      throw const ApiException('No se pudo conectar con el servidor. Verifique su conexión.');
    }

    final status = response.statusCode;
    if (status >= 200 && status < 300) {
      return response.body.isEmpty ? null : jsonDecode(utf8.decode(response.bodyBytes));
    }

    final mensaje = _mensajeDeError(response);
    if (status == 401 && authenticated) {
      onUnauthorized?.call();
      throw UnauthorizedException(mensaje ?? 'Su sesión expiró. Inicie sesión de nuevo.');
    }
    throw ApiException(mensaje ?? _mensajePorEstado(status), statusCode: status);
  }

  /// La API responde errores como { "error": "..." }.
  static String? _mensajeDeError(http.Response response) {
    try {
      final data = jsonDecode(utf8.decode(response.bodyBytes));
      if (data is Map && data['error'] is String) return data['error'] as String;
    } on FormatException {
      // Cuerpo vacío o no JSON: se usa el mensaje por estado.
    }
    return null;
  }

  static String _mensajePorEstado(int status) => switch (status) {
        400 => 'La solicitud no es válida.',
        401 => 'Usuario o contraseña incorrectos.',
        403 => 'No tiene permisos para realizar esta operación.',
        404 => 'El recurso solicitado no existe.',
        429 => 'Demasiados intentos. Espere un momento.',
        _ => 'Ocurrió un error en el servidor. Intente más tarde.',
      };
}
