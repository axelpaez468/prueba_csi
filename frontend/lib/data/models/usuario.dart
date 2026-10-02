/// Usuario del sistema, tal como lo devuelve la administración de usuarios.
class Usuario {
  const Usuario({
    required this.id,
    required this.nombre,
    required this.apellido,
    required this.nombreCompleto,
    required this.email,
    required this.telefono,
    required this.codigoCorporativo,
    required this.rol,
    required this.activo,
    required this.dosFactor,
    required this.tieneContrasena,
  });

  final int id;
  final String nombre;
  final String apellido;
  final String nombreCompleto;
  final String email;

  /// E.164: +50255550101.
  final String telefono;
  final String codigoCorporativo;
  final String rol;
  final bool activo;
  final String dosFactor;

  /// false: fue invitado y todavía no creó su contraseña.
  final bool tieneContrasena;

  bool get esAdmin => rol == 'ADMIN';

  /// 8 dígitos locales, sin el prefijo +502.
  String get telefonoLocal => telefono.startsWith('+502') ? telefono.substring(4) : telefono;

  /// "+502 5555 0101".
  String get telefonoFormateado {
    final l = telefonoLocal;
    return l.length == 8 ? '+502 ${l.substring(0, 4)} ${l.substring(4)}' : telefono;
  }

  String get iniciales =>
      '${nombre.isEmpty ? '' : nombre[0]}${apellido.isEmpty ? '' : apellido[0]}'.toUpperCase();

  factory Usuario.fromJson(Map<String, dynamic> j) => Usuario(
        id: j['id'] as int,
        nombre: j['nombre'] as String,
        apellido: j['apellido'] as String,
        nombreCompleto: j['nombreCompleto'] as String,
        email: j['email'] as String,
        telefono: j['telefono'] as String,
        codigoCorporativo: j['codigoCorporativo'] as String,
        rol: j['rol'] as String,
        activo: j['activo'] as bool,
        dosFactor: j['dosFactor'] as String,
        tieneContrasena: j['tieneContrasena'] as bool,
      );
}

/// Datos del formulario de alta/edición. El teléfono va con 8 dígitos: el servidor antepone +502.
class DatosUsuario {
  const DatosUsuario({
    required this.nombre,
    required this.apellido,
    required this.telefono,
    required this.email,
    required this.codigoCorporativo,
    required this.rol,
  });

  final String nombre;
  final String apellido;
  final String telefono;
  final String email;
  final String codigoCorporativo;
  final String rol;

  Map<String, dynamic> toJson() => {
        'nombre': nombre,
        'apellido': apellido,
        'telefono': telefono,
        'email': email,
        'codigoCorporativo': codigoCorporativo,
        'rol': rol,
      };
}
