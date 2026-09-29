/// Sesión del usuario autenticado. El token nunca se imprime: [toString] lo omite.
class Session {
  const Session({
    required this.token,
    required this.username,
    required this.rol,
    required this.expiraEn,
  });

  final String token;
  final String username;
  final String rol;
  final DateTime expiraEn;

  bool get esVendedor => rol == 'VENDEDOR';

  bool get expirada => DateTime.now().toUtc().isAfter(expiraEn);

  factory Session.fromJson(Map<String, dynamic> json) => Session(
        token: json['token'] as String,
        username: json['username'] as String,
        rol: json['rol'] as String,
        expiraEn: DateTime.parse(json['expiraEn'] as String).toUtc(),
      );

  Map<String, dynamic> toJson() => {
        'token': token,
        'username': username,
        'rol': rol,
        'expiraEn': expiraEn.toIso8601String(),
      };

  @override
  String toString() => 'Session(username: $username, rol: $rol)';
}
