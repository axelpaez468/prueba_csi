/// Configuración por entorno. Se inyecta en tiempo de compilación:
///   flutter run -d chrome --dart-define=API_URL=http://localhost:5080
/// Nada sensible debe ir aquí: todo lo que se compila queda visible en el bundle web.
class AppConfig {
  const AppConfig._();

  static const String apiUrl = String.fromEnvironment('API_URL');

  static bool get isValid => Uri.tryParse(apiUrl)?.hasScheme ?? false;

  /// Foto de un producto (endpoint público de la API; se puede guardar en caché).
  static String urlImagen(int productoId, int imagenId) =>
      '${apiUrl.endsWith('/') ? apiUrl.substring(0, apiUrl.length - 1) : apiUrl}/api/productos/$productoId/imagenes/$imagenId';
}
