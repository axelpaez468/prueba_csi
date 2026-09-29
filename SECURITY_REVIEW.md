# Revisión de seguridad — Fragmentos A y B

Escala de severidad:

| Severidad | Criterio |
|---|---|
| **Crítica** | Explotable de forma remota y sin credenciales; compromete cuentas, datos o dinero. |
| **Alta** | Expone datos de otros usuarios o secretos, o facilita un ataque grave. |
| **Media** | Debilita una defensa o filtra información útil para un atacante. |
| **Baja** | Mala práctica o fallo de robustez sin impacto directo de seguridad. |

---

## Fragmento A — Backend (C#)

| # | Severidad | Problema | Impacto | Corrección |
|---|---|---|---|---|
| A1 | **Crítica** | **Contraseña maestra en el código**: `if (dto.Password == "admin123") return GenerarToken("admin", "ADMIN")`. | Cualquiera que conozca (o adivine) `admin123` obtiene un token ADMIN con **cualquier** usuario, aunque no exista. Es una puerta trasera, y además queda en el historial de Git. | Eliminarla. Ningún acceso se concede fuera de la verificación normal contra la BD. Si hace falta un administrador inicial, se crea con un script de siembra y una contraseña que viene de una variable de entorno. |
| A2 | **Crítica** | **Inyección SQL**: la consulta se arma por interpolación (`$"... WHERE Username = '{dto.Username}' ..."`). | Con usuario `' OR 1=1 --` se entra como el primer usuario de la tabla (normalmente un admin) sin contraseña. También permite leer o modificar cualquier tabla (`; DROP TABLE ...`, `UNION SELECT ...`). | Consultas parametrizadas: `QueryFirstOrDefaultAsync<Usuario>("SELECT Id, Username, PasswordHash, Rol FROM Usuarios WHERE Username = @Username", new { dto.Username })`, o EF Core/LINQ, que parametriza siempre. |
| A3 | **Crítica** | **Contraseñas en texto plano**: se comparan en SQL contra la columna `Password`, lo que implica que se guardan tal cual. | Una sola fuga de la BD (backup, inyección, empleado) expone todas las contraseñas, que la gente reutiliza en otros servicios. | Guardar solo un hash lento con sal (BCrypt, PBKDF2 o Argon2) en `PasswordHash`. Buscar al usuario por nombre y verificar con `BCrypt.Verify(dto.Password, user.PasswordHash)`. Nunca comparar contraseñas en SQL. |
| A4 | **Crítica** | **Clave JWT débil y en el código**: `const string JwtKey = "clave-secreta"`. | Tiene 13 bytes (HS256 necesita al menos 32), es adivinable y está en el repositorio. Con ella, cualquiera puede **fabricar tokens válidos** con rol ADMIN y hacerse pasar por cualquier usuario. | Leerla de una variable de entorno o de un gestor de secretos (`Jwt__Key`), exigir al menos 32 bytes aleatorios y que la aplicación **no arranque** si falta. Rotarla, porque la actual ya quedó expuesta. |
| A5 | **Alta** | **Autorización a nivel de recurso ausente** en `GET /api/pedidos/{id}`: el endpoint no exige autenticación ni verifica el dueño. | Cualquiera, incluso sin sesión, puede recorrer `/api/pedidos/1`, `/2`, `/3`... y leer los pedidos de todos (IDOR). | `.RequireAuthorization()` y filtrar en la propia consulta: `WHERE Id = @id AND (UsuarioId = @usuarioActual OR @esAdmin = 1)`. Si no hay resultado, devolver **404**, sin revelar si el pedido existe. |
| A6 | **Alta** | **Filtración de detalles internos**: `Results.Problem(ex.ToString())`. | La respuesta incluye el stack trace, rutas del servidor, nombres de tablas y mensajes de SQL Server, información muy útil para afinar un ataque. | Registrar la excepción en el log del servidor y devolver al cliente un mensaje genérico (`{ "error": "Ocurrió un error inesperado" }`) con un manejador global (`IExceptionHandler`). |
| A7 | **Media** | **Enumeración de usuarios**: el mensaje incluye el usuario (`$"Usuario {dto.Username} no existe o clave incorrecta"`). | Refleja la entrada del usuario (riesgo de inyección de contenido si el cliente lo renderiza como HTML). El texto sugiere distinguir los casos y ayuda a confirmar qué usuarios existen. | Mensaje único y genérico: "Usuario o contraseña incorrectos". Además, verificar contra un hash ficticio cuando el usuario no existe, para que el tiempo de respuesta tampoco lo delate. |
| A8 | **Media** | **Código de estado incorrecto**: credenciales inválidas devuelven **400** en lugar de **401**. | Los clientes no pueden distinguir "petición mal formada" de "no autenticado", y el monitoreo de intentos fallidos se vuelve más difícil. | Devolver `401 Unauthorized` con el formato de error estándar. |
| A9 | **Media** | **Sin límite de intentos** en el login. | Permite fuerza bruta y *credential stuffing* sin freno. | Rate limiting por IP o usuario (`AddRateLimiter` de ASP.NET Core) y, opcionalmente, bloqueo temporal tras N fallos. |
| A10 | **Media** | **`SELECT *`** tanto en el login como en pedidos. | Trae columnas innecesarias (el hash de contraseña viaja por toda la aplicación) y cualquier columna nueva queda expuesta automáticamente en la respuesta de pedidos. | Seleccionar columnas explícitas y responder con DTOs, no con la entidad. |
| A11 | **Baja** | **`QueryFirstAsync` para "no encontrado"**: si el pedido no existe lanza una excepción que termina en 500, con el stack trace del punto A6. | Un caso normal (404) se convierte en error del servidor. | `QueryFirstOrDefaultAsync` y `return pedido is null ? Results.NotFound(...) : Results.Ok(dto)`. |
| A12 | **Baja** | **Ruta inconsistente**: `/api/login` en vez de `/api/auth/login`, y sin validar entrada nula. | `dto.Username` nulo provoca una excepción; la ruta no coincide con el contrato. | Validar el DTO (campos obligatorios) y alinear la ruta con el contrato. |

### Fragmento A corregido (referencia)

```csharp
app.MapPost("/api/auth/login", async (LoginDto dto, IDbConnection db, TokenService tokens) =>
{
    if (string.IsNullOrWhiteSpace(dto.Username) || string.IsNullOrEmpty(dto.Password))
        return Results.BadRequest(new { error = "Usuario y contraseña son obligatorios." });

    var user = await db.QueryFirstOrDefaultAsync<Usuario>(
        "SELECT Id, Username, PasswordHash, Rol FROM Usuarios WHERE Username = @Username",
        new { dto.Username });

    var ok = BCrypt.Net.BCrypt.Verify(dto.Password, user?.PasswordHash ?? HashFicticio);
    return user is not null && ok
        ? Results.Ok(tokens.Generar(user))
        : Results.Json(new { error = "Usuario o contraseña incorrectos." }, statusCode: 401);
}).RequireRateLimiting("login");

app.MapGet("/api/pedidos/{id:int}", async (int id, ClaimsPrincipal user, IDbConnection db) =>
{
    var pedido = await db.QueryFirstOrDefaultAsync<PedidoDto>(
        """
        SELECT Id, UsuarioId, Fecha, Total FROM Pedidos
        WHERE Id = @id AND (UsuarioId = @usuarioId OR @esAdmin = 1)
        """,
        new { id, usuarioId = user.GetUsuarioId(), esAdmin = user.IsInRole("ADMIN") });

    return pedido is null ? Results.NotFound(new { error = "Pedido no encontrado." }) : Results.Ok(pedido);
}).RequireAuthorization();

// La clave se lee de la configuración (variable de entorno Jwt__Key) y se valida al arrancar:
var jwtKey = builder.Configuration["Jwt:Key"];
if (jwtKey is null || Encoding.UTF8.GetByteCount(jwtKey) < 32)
    throw new InvalidOperationException("Jwt__Key no definida o menor a 32 bytes.");
// Los errores no controlados pasan por un IExceptionHandler que responde { "error": "..." } genérico.
```

La implementación completa de estas correcciones está en `backend/src/Pedidos.Api`: `AuthService`, `PedidoService.ObtenerAsync`, `GlobalExceptionHandler`, `JwtOptions` y `Program.cs`.

---

## Fragmento B — Frontend (Dart)

| # | Severidad | Problema | Impacto | Corrección |
|---|---|---|---|---|
| B1 | **Crítica** | **Secreto en el bundle**: `const apiKey = 'sk_live_9f8a7b6c5d4e'`. | Todo lo que se compila en una app web (o móvil) es público: basta abrir `main.dart.js`. Es una clave de **producción** (`sk_live_`) que quedó expuesta a cualquiera, y también en el historial de Git. | **Revocar la clave de inmediato** y emitir una nueva. Las claves de servicios externos solo viven en el backend (variables de entorno o gestor de secretos). El frontend se autentica **con el JWT del usuario**; si necesita algo de un servicio externo, lo pide al backend, que actúa de intermediario. |
| B2 | **Crítica** | **El cliente calcula y envía el total** (`'total': total`) y **envía precios** (`jsonEncode(carrito)` serializa `precio`). | Cualquiera puede modificar la petición (DevTools, Postman) y comprar a Q0.01. Si el backend confía en esos valores, hay **fraude directo**. | El frontend envía **solo `productoId` y `cantidad`**. El servidor toma el precio vigente de la BD y calcula subtotales y total. En pantalla, el total antes de confirmar es solo *referencial*; el definitivo es el que devuelve la API. |
| B3 | **Crítica** | **Credenciales en la URL**: `login?user=$user&pass=$pass`. | La contraseña queda en los logs del servidor web, proxies y balanceadores, en el historial del navegador y en la cabecera `Referer`. | Enviar las credenciales en el **cuerpo** de un `POST` con `Content-Type: application/json`, y siempre sobre HTTPS. |
| B4 | **Alta** | **Sin HTTPS**: `apiUrl = 'http://api.miempresa.com'`. | Credenciales, token y datos viajan en claro; cualquiera en la misma red (Wi-Fi pública, proxy) puede leerlos o modificarlos. | `https://` obligatorio fuera de desarrollo, HSTS en el servidor, y la URL configurada por entorno (`--dart-define=API_URL=...`), no fija en el código. |
| B5 | **Alta** | **Token en `SharedPreferences`**. | Se guarda en texto plano (en web, en `localStorage`; en Android, en un XML legible en dispositivos rooteados o por backups). | Usar `flutter_secure_storage` (Keychain en iOS, Keystore en Android; cifrado en web). En web, además, expiración corta del token y una CSP estricta para reducir el riesgo de XSS. |
| B6 | **Alta** | **Token impreso en consola**: `print('Token obtenido: $token')`. | Queda en los logs del dispositivo o del navegador, en herramientas de reporte de errores y en capturas de pantalla compartidas al pedir soporte. | Nunca registrar tokens ni credenciales. Quitar el `print`; si hace falta depurar, usar `debugPrint` sin datos sensibles y un lint (`avoid_print`). |
| B7 | **Alta** | **`confirmarPedido` no envía el token** (usa `X-Api-Key`, no `Authorization: Bearer`). | El pedido no queda asociado al vendedor autenticado; el backend no puede aplicar autorización por rol ni por dueño. En la práctica, cualquiera con la API key puede crear pedidos a nombre de nadie. | Enviar `Authorization: Bearer <token>` en todas las peticiones autenticadas, desde un cliente HTTP centralizado. |
| B8 | **Media** | **No se revisa la respuesta**: ni `login` ni `confirmarPedido` miran `statusCode`. | Con credenciales inválidas, `jsonDecode(res.body)['token']` es `null` y se guarda `null` (o lanza una excepción). Un 400 por falta de stock o un 401 pasan en silencio y el usuario cree que el pedido se creó. | Verificar el código de estado. En 2xx procesar la respuesta; en 400 mostrar el `error` del servidor; en 401 cerrar la sesión y volver al login. Agregar *timeout* y manejo de errores de red. |
| B9 | **Media** | **Sin protección contra doble envío** en `confirmarPedido`. | Un doble clic crea dos pedidos y descuenta stock dos veces. | Deshabilitar el botón y mostrar un indicador de carga mientras la petición está en curso; ignorar invocaciones concurrentes. En el backend, idealmente una clave de idempotencia. |
| B10 | **Baja** | **Aritmética de dinero con `double`** (`fold(0.0, ...)`). | Errores de redondeo (0.1 + 0.2 ≠ 0.3). Con B2 corregido solo afecta al total referencial. | Usar decimales o enteros en centavos para cualquier cálculo que se muestre como importe, y tratar el total del servidor como el único válido. |
| B11 | **Baja** | **`jsonEncode(carrito)`** depende de que `Linea` tenga `toJson()` y serializa lo que contenga. | Envía campos no previstos (precio, nombre, etc.) o falla en tiempo de ejecución. | DTO explícito: `{'lineas': carrito.map((l) => {'productoId': l.productoId, 'cantidad': l.cantidad}).toList()}`. |

### Fragmento B corregido (referencia)

```dart
// La URL llega por entorno: flutter build web --dart-define=API_URL=https://api.miempresa.com
const apiUrl = String.fromEnvironment('API_URL');
// Sin apiKey: ningún secreto vive en el frontend.

final _storage = const FlutterSecureStorage();

Future<void> login(String user, String pass) async {
  final res = await http.post(
    Uri.parse('$apiUrl/api/auth/login'),
    headers: {'Content-Type': 'application/json'},
    body: jsonEncode({'username': user, 'password': pass}),
  );
  if (res.statusCode != 200) throw ApiException(_mensajeError(res));
  final token = jsonDecode(res.body)['token'] as String;
  await _storage.write(key: 'token', value: token); // sin print
}

Future<Pedido> confirmarPedido(List<Linea> carrito) async {
  final token = await _storage.read(key: 'token');
  final res = await http.post(
    Uri.parse('$apiUrl/api/pedidos'),
    headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $token'},
    body: jsonEncode({
      'lineas': [for (final l in carrito) {'productoId': l.productoId, 'cantidad': l.cantidad}],
    }), // sin precios ni total
  );
  if (res.statusCode == 401) { await cerrarSesion(); throw const SesionExpirada(); }
  if (res.statusCode != 201) throw ApiException(_mensajeError(res));
  return Pedido.fromJson(jsonDecode(res.body)); // el total que se muestra es el del servidor
}
```

La implementación real está en `frontend/lib`: `core/network/api_client.dart`, `core/security/token_storage.dart`, `data/repositories/*` y `features/cart/cart_controller.dart`.

---

## Resumen

| Severidad | Fragmento A | Fragmento B | Total |
|---|---|---|---|
| Crítica | 4 | 3 | 7 |
| Alta | 2 | 4 | 6 |
| Media | 4 | 2 | 6 |
| Baja | 2 | 2 | 4 |

**Acciones inmediatas** (antes de cualquier otro cambio):
1. Revocar la clave `sk_live_9f8a7b6c5d4e`.
2. Rotar la clave JWT e invalidar los tokens emitidos con ella.
3. Eliminar la contraseña maestra.
4. Forzar el cambio de contraseñas: estuvieron en texto plano y el login era inyectable.
5. Purgar esos secretos del historial de Git (`git filter-repo`), porque borrarlos en un commit nuevo no basta.
