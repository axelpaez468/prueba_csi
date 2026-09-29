# Sistema de Pedidos — API .NET 8 + Flutter Web

Los vendedores inician sesión, consultan el catálogo, arman un carrito y confirman pedidos. Al confirmar, el servidor descuenta el inventario.
**Toda la lógica de negocio vive en el backend.** El frontend muestra datos y captura acciones, pero no decide precios, totales ni stock.

```
backend/            API ASP.NET Core 8 + EF Core (SQL Server) y sus pruebas (xUnit)
frontend/           Aplicación Flutter Web y sus pruebas
db/                 init.sql (esquema + semilla) y scripts de arranque del contenedor de SQL Server
docker-compose.yml  db + api + frontend
.env.example        Variables necesarias (copiar a .env)
SECURITY_REVIEW.md  Revisión de código de los fragmentos A y B
MENSAJE_PM.md       Mensaje al jefe de proyecto
```

---

## 1. Cómo levantar el proyecto

### Con Docker (recomendado)

Requisitos: Docker Desktop (o Docker Engine + Compose v2) con al menos 4 GB de RAM asignados.

```bash
cp .env.example .env        # y cambiar las contraseñas y JWT_KEY
docker compose up --build
```

| Servicio | URL |
|---|---|
| Frontend | http://localhost:8080 |
| API | http://localhost:5080 |

- El primer build tarda bastante: descarga SQL Server (unos 1.5 GB), el SDK de .NET y Flutter.
- La base de datos se crea sola. El contenedor `db` arranca SQL Server, ejecuta `db/init/init.sql` y solo entonces el *healthcheck* lo marca como sano. La API espera a ese estado (`depends_on: service_healthy`).
- Los datos persisten en el volumen `mssql-data`. Para empezar de cero: `docker compose down -v`.
- `JWT_KEY` debe tener al menos 32 caracteres; si no, la API no arranca. Para generarla: `openssl rand -base64 48`.

### Sin Docker (desarrollo)

**Base de datos:** cualquier SQL Server 2019 o posterior. Con autenticación de Windows y una instancia `.\SQLEXPRESS`:

```bash
sqlcmd -S ".\SQLEXPRESS" -E -b -I -f 65001 -i db/init/init.sql -v DB_NAME=PedidosDb APP_DB_USER=pedidos_app APP_DB_PASSWORD="Cambiar-App-2026!"
```

**API** (http://localhost:5080, con Swagger en `/swagger`). Los secretos van en *user-secrets*, fuera del repositorio:

```bash
cd backend
dotnet user-secrets set "Jwt:Key" "<clave aleatoria de 32+ caracteres>" --project src/Pedidos.Api
dotnet user-secrets set "ConnectionStrings:Default" "Server=.\SQLEXPRESS;Database=PedidosDb;Trusted_Connection=True;TrustServerCertificate=True" --project src/Pedidos.Api
dotnet run --project src/Pedidos.Api --launch-profile http
```

**Frontend.** En desarrollo, CORS permite `http://localhost:8080` y `http://localhost:8081`:

```bash
cd frontend
flutter run -d chrome --web-port 8081 --dart-define=API_URL=http://localhost:5080
```

> **Nota (Windows):** si la ruta del proyecto tiene caracteres no ASCII (tildes, ñ), `flutter analyze` falla por un error conocido del analizador de Dart. Se evita mapeando la carpeta a una unidad: `subst P: "<ruta del proyecto>"` y trabajando desde `P:\frontend`.

---

## 2. Usuarios de prueba

| Usuario | Contraseña | Rol | Puede |
|---|---|---|---|
| `vendedor` | `Vendedor123!` | VENDEDOR | Ver el catálogo, crear pedidos y ver **sus** pedidos |
| `admin` | `Admin123!` | ADMIN | Ver el catálogo y **cualquier** pedido; no crea pedidos |

Productos semilla: 5, entre ellos el **Monitor 27" con stock 1**, para probar la concurrencia, y la **Webcam HD con stock 0**, que aparece deshabilitada en el catálogo.
Son credenciales de prueba y están guardadas como hash BCrypt en `init.sql`.

---

## 3. Cómo probar la API

- **Colección `.http`:** [`backend/src/Pedidos.Api/Pedidos.Api.http`](backend/src/Pedidos.Api/Pedidos.Api.http) trae 14 casos (login, catálogo, pedido feliz, 400, 401, 403 y 404). Se ejecuta con VS Code + REST Client, o directamente en Visual Studio o Rider. El token se encadena solo entre peticiones.
- **Swagger:** http://localhost:5080/swagger (solo en entorno Development).
- **curl** (Git Bash, Linux o macOS):

```bash
# Login (guarda el token)
TOKEN=$(curl -s -X POST http://localhost:5080/api/auth/login -H "Content-Type: application/json" \
  -d '{"username":"vendedor","password":"Vendedor123!"}' | sed -E 's/.*"token":"([^"]+)".*/\1/')

# Catálogo
curl -i http://localhost:5080/api/productos -H "Authorization: Bearer $TOKEN"

# Crear pedido: el precio y el total enviados se IGNORAN
curl -i -X POST http://localhost:5080/api/pedidos -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{"lineas":[{"productoId":1,"cantidad":2,"precio":0.01},{"productoId":2,"cantidad":1}],"total":0.01}'

# Consultar pedido (dueño o ADMIN; si es ajeno responde 404)
curl -i http://localhost:5080/api/pedidos/1 -H "Authorization: Bearer $TOKEN"

# Errores 400: cantidad 0, producto duplicado, inexistente, stock insuficiente
curl -i -X POST http://localhost:5080/api/pedidos -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{"lineas":[{"productoId":1,"cantidad":0}]}'

# Concurrencia: 10 pedidos simultáneos por la última unidad -> un 201 y nueve 400
for i in $(seq 1 10); do curl -s -o /dev/null -w "%{http_code}\n" -X POST http://localhost:5080/api/pedidos \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{"lineas":[{"productoId":3,"cantidad":1}]}' & done; wait
```

### Endpoints

| Método | Ruta | Acceso | Respuestas |
|---|---|---|---|
| POST | `/api/auth/login` | Público (10 intentos/min por IP) | 200 `{ token, expiraEn, username, rol }` · 400 · 401 · 429 |
| GET | `/api/productos` | Autenticado | 200 `[{ id, codigo, nombre, precio, stock }]` · 401 |
| POST | `/api/pedidos` | VENDEDOR | 201 `{ numero, fecha, usuarioId, total, lineas[] }` · 400 · 401 · 403 |
| GET | `/api/pedidos/{id}` | Dueño o ADMIN | 200 · 401 · 404 |

Todos los errores tienen el mismo formato: `{ "error": "mensaje legible" }`.

### Pruebas automatizadas

```bash
cd backend && dotnet test      # 15 pruebas (1 se omite si no hay SQL Server; ver abajo)
cd frontend && flutter test    # 28 pruebas
```

- **Backend:** usa SQLite en memoria, que a diferencia del proveedor InMemory de EF soporta transacciones reales, `ExecuteUpdate` y *check constraints*. Cubre: precio/total calculados en el servidor aunque el cliente los envíe; descuento de stock; rollback completo si una línea falla; última unidad vendida una sola vez; cantidad ≤ 0; producto inexistente; producto duplicado; pedido vacío; pedido ajeno no visible; y login válido/inválido.
- **Concurrencia real contra SQL Server:** la prueba lanza 20 pedidos simultáneos por la última unidad. Se activa definiendo `PEDIDOS_TEST_SQLSERVER` con una cadena de conexión (usuario con permiso para crear bases), por ejemplo `Server=.\SQLEXPRESS;Trusted_Connection=True;TrustServerCertificate=True`.
- **Frontend:** repositorio de pedidos (envía solo `productoId` y `cantidad` con `Bearer`, usa el total del servidor y maneja 400 y 401), carrito (subtotal referencial y **doble clic = un solo pedido**) y widget de catálogo (producto sin stock deshabilitado). Además, **pruebas de layout responsive**: login, catálogo, carrito y comprobante se renderizan a 320, 375, 768, 1366 y 1920 px, y cualquier desborde hace fallar la prueba.

---

## 4. Decisiones técnicas

### Backend

| Decisión | Justificación |
|---|---|
| **Descuento de stock con un `UPDATE` condicional**: `UPDATE Productos SET Stock = Stock - @n WHERE Id = @id AND Stock >= @n` (EF Core `ExecuteUpdateAsync`) y comprobar las filas afectadas. | La verificación y la resta ocurren en **una sola sentencia atómica** con bloqueo de fila. Si dos pedidos compiten por la última unidad, el segundo espera al primero, reevalúa `Stock >= @n` y afecta 0 filas, así que se rechaza. Evita el clásico "leer stock → validar → restar", que tiene condición de carrera, sin recurrir a niveles de aislamiento altos ni a reintentos. Se verificó con 10 peticiones HTTP simultáneas (1 × 201, 9 × 400) y con una prueba automatizada contra SQL Server. |
| Líneas procesadas **en orden de `ProductoId`**. | Dos pedidos con los mismos productos bloquean las filas en el mismo orden, lo que evita *deadlocks*. |
| **Una transacción** que abarca la validación, el descuento, la cabecera y el detalle. | Si cualquier línea falla, se deshace todo; nunca queda stock descontado sin pedido. |
| `CHECK (Stock >= 0)`, `CHECK (Cantidad > 0)` y PK `(PedidoId, ProductoId)` en la BD. | Defensa en profundidad: aunque falle la lógica de la aplicación, la base de datos no acepta estados inválidos. |
| El DTO de entrada solo tiene `productoId` y `cantidad`. | Si el cliente envía `precio` o `total`, el deserializador los descarta; el precio sale de la BD dentro de la transacción. |
| **404 (no 403)** al pedir un pedido ajeno; el filtro va **en la consulta** (`WHERE Id = @id AND (UsuarioId = @yo OR @esAdmin)`). | No revela si ese número de pedido existe, y no hay forma de "olvidarse" del chequeo después de cargar el dato. |
| Política de autorización **por defecto = autenticado** (`FallbackPolicy`), con `[AllowAnonymous]` solo en el login. | Seguro por defecto: un endpoint nuevo no queda público por olvido. |
| `BusinessRuleException` + `IExceptionHandler` global → `{ "error": "..." }`. | Formato de error único. Los 500 se registran en el log y el cliente recibe un mensaje genérico, sin stack trace ni mensajes de SQL. |
| **Controllers** en lugar de Minimal APIs. | Validación de modelo, `[Authorize(Roles=...)]` y `CreatedAtAction` de forma declarativa y fácil de revisar. |
| EF Core para el acceso a datos. | Todas las consultas se parametrizan. El esquema lo define `init.sql`, que es la única fuente de verdad, y el `DbContext` lo mapea (sin migraciones, para mantener un solo script de inicialización). |
| JWT HS256 con `Jwt__Key` desde variables de entorno o user-secrets; la app **no arranca** si la clave falta o mide menos de 32 bytes. Expiración de 60 min y `ClockSkew` de 30 s. | Evita arrancar en producción con una clave débil o por defecto. |
| BCrypt (work factor 11) y verificación contra un **hash ficticio** cuando el usuario no existe. | El tiempo de respuesta no permite descubrir qué usuarios existen. |
| Rate limiting en el login (10 por minuto por IP). | Frena la fuerza bruta. |
| CORS con **orígenes explícitos** (`Cors__AllowedOrigins`); la app no arranca si se configura `*`. Solo `GET`/`POST` y las cabeceras `Authorization`/`Content-Type`. | Superficie mínima. |
| La API se conecta con el login **`pedidos_app`** (`db_datareader` + `db_datawriter`), no con `sa`. | Mínimo privilegio: si la API se viera comprometida, no podría alterar el esquema ni otras bases. |

### Frontend

| Decisión | Justificación |
|---|---|
| **Provider + `ChangeNotifier`** para el estado. | El estado es poco y claro: sesión, catálogo y carrito. Provider es el enfoque recomendado en la documentación oficial para este tamaño de app, sin generación de código y con poco *boilerplate*. Cada controlador es una clase Dart simple, testeable sin widgets. Riverpod o Bloc aportarían más estructura de la que este alcance necesita. |
| Capas `lib/core` (config, red, seguridad), `lib/data` (modelos y repositorios) y `lib/features` (pantallas y controladores). | Las pantallas no conocen HTTP; los repositorios no conocen widgets. |
| `ApiClient` único. | Agrega el `Bearer`, traduce `{ "error" }` a mensajes legibles y, ante un **401**, dispara el cierre de sesión. La app entonces vuelve al Login, cierra las pantallas abiertas y vacía el carrito. |
| Token en **`flutter_secure_storage`**, nunca en logs (`Session.toString()` lo omite y no hay `print`). | Requisito del enunciado. En web se guarda cifrado con WebCrypto; ver "Pendiente". |
| `LineaPedido.toJson()` solo produce `{productoId, cantidad}`. | Una prueba verifica que el cuerpo no contenga `precio` ni `total`. El total que se muestra al confirmar es el devuelto por la API. |
| Botón "Confirmar" deshabilitado y con indicador mientras se procesa; además, `CartController.confirmar()` ignora llamadas concurrentes. | Doble protección contra pedidos duplicados por doble clic. |
| `API_URL` por `--dart-define`; si falta, la app muestra un aviso en lugar de fallar. | Configuración por entorno, sin URLs fijas. |
| Build web con `--no-web-resources-cdn`. | CanvasKit se sirve desde el propio nginx: la app no depende de un CDN externo y funciona en redes cerradas. |

### Docker

| Decisión | Justificación |
|---|---|
| **API:** multi-stage `sdk:8.0` → `aspnet:8.0`, con `USER $APP_UID` (no root, UID 1654). | La imagen final no lleva SDK ni código fuente. |
| **Frontend:** multi-stage `debian:bookworm-slim` + **Flutter 3.47.5 fijado** desde el repositorio oficial → `nginx-unprivileged` (no root, puerto 8080). | Build reproducible con la misma versión usada en desarrollo. Las imágenes públicas de Flutter no tienen esa versión y además incluyen el SDK de Android (unos 3 GB innecesarios). |
| **Tres servicios.** La inicialización de la BD va dentro del contenedor `db` (`db/entrypoint.sh`), no en un cuarto servicio. | El *healthcheck* solo reporta "sano" cuando `init.sql` terminó **y** la tabla responde, así que `depends_on: service_healthy` garantiza que la API arranca con el esquema listo. `init.sql` es idempotente y se aplica en cada arranque sin duplicar datos. |
| El puerto de SQL Server **no se publica**. | Solo la API accede a la base de datos, por la red interna de Compose. |
| Secretos solo en `.env` (ignorado por Git); `.env.example` documenta cada variable; `${VAR:?}` falla con un mensaje claro si falta alguna. | Ningún secreto en el repositorio. |

---

## 5. Seguridad (checklist 4a)

| Requisito | Dónde |
|---|---|
| Hash robusto de contraseñas | BCrypt: `AuthService`, hashes en `init.sql` |
| Consultas 100 % parametrizadas | EF Core LINQ y `ExecuteUpdateAsync`; no hay SQL concatenado |
| Autorización a nivel de recurso | `PedidoService.ObtenerAsync`: filtro por dueño en la consulta, 404 si es ajeno (probado) |
| Errores sin stack traces ni mensajes de BD | `GlobalExceptionHandler`, `InvalidModelStateResponseFactory`, eventos `OnChallenge`/`OnForbidden` del JWT |
| Clave JWT desde entorno y con longitud adecuada | `JwtOptions.Validar()` (≥ 32 bytes, falla al arrancar) |
| Bundle del frontend sin secretos | Solo `API_URL`, que es pública; no hay claves ni credenciales en `lib/` |

La revisión de los fragmentos A y B está en [SECURITY_REVIEW.md](SECURITY_REVIEW.md).

---

## 6. Pendiente y posibles mejoras

| Tema | Estado y cómo se resolvería |
|---|---|
| HTTPS | Compose expone HTTP porque es un entorno local. En producción, TLS se termina en un reverse proxy o balanceador (nginx, Traefik o un load balancer gestionado), con HSTS y `API_URL=https://...`. |
| Token en web | `flutter_secure_storage` en web cifra con WebCrypto, pero la clave también vive en el navegador, así que un XSS podría leerlo. En producción: cookie `HttpOnly; Secure; SameSite=Strict` emitida por el backend (o un BFF), más una CSP estricta. |
| Refresh tokens / revocación | Hoy el token dura 60 min y cerrar sesión solo lo borra del cliente. Se agregaría un refresh token rotativo guardado en BD y una lista de revocación (`jti`). |
| Idempotencia al crear pedidos | El doble clic está cubierto en la UI. Para reintentos de red, el cliente enviaría un `Idempotency-Key` y la API guardaría la respuesta asociada a esa clave. |
| Migraciones | El esquema lo gestiona `init.sql`. Con evolución del modelo se pasaría a migraciones versionadas (EF Core Migrations o DbUp). |
| Rate limit distribuido | El límite de login es en memoria (por instancia). Con varias réplicas iría en Redis o en el gateway. |
| Observabilidad | Logs estructurados y *health checks* de dependencias (`/health` hoy no consulta la BD). |
| Paginación del catálogo | No hace falta con 5 productos; con catálogos grandes: `?page=&size=` y búsqueda. |

---

## 7. Uso de asistentes de IA

Se utilizó **Claude Code (Anthropic)** como asistente durante toda la prueba, para:

- instalar y verificar el entorno (.NET 8, Flutter, Docker);
- generar el código del backend, del frontend y de Docker, y los scripts SQL;
- escribir y ejecutar las pruebas automatizadas y las pruebas manuales de punta a punta (API con curl y la app en el navegador);
- redactar SECURITY_REVIEW.md, MENSAJE_PM.md y este README.

Las decisiones de diseño se revisaron y validaron ejecutando el sistema: reglas de negocio, concurrencia con peticiones simultáneas reales, flujo 401 → login y ausencia del token en consola y almacenamiento.
