/// Configuración por entorno. Se inyecta en tiempo de compilación:
///   flutter run -d chrome --dart-define=API_URL=http://localhost:5080
/// Nada sensible debe ir aquí: todo lo que se compila queda visible en el bundle web.
class AppConfig {
  const AppConfig._();

  static const String apiUrl = String.fromEnvironment('API_URL');

  static bool get isValid => Uri.tryParse(apiUrl)?.hasScheme ?? false;
}
