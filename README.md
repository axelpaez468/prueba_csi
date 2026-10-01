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
| Bandeja de correos de prueba (Mailpit), si no se configura un SMTP real | http://localhost:8025 |

- El primer build tarda bastante: descarga SQL Server (unos 1.5 GB), el SDK de .NET y Flutter.
- La base de datos se crea sola. El contenedor `db` arranca SQL Server, ejecuta `db/init/init.sql` y solo entonces el *healthcheck* lo marca como sano. La API espera a ese estado (`depends_on: service_healthy`).
- Los datos persisten en el volumen `mssql-data`. Para empezar de cero: `docker compose down -v`.
- `JWT_KEY` debe tener al menos 32 caracteres, y `SEGURIDAD_CLAVE_MAESTRA` debe ser una clave de 32 bytes en Base64; si falta alguna, la API no arranca. Para generarlas: `openssl rand -base64 48` y `openssl rand -base64 32`.
- Si ya tenías el volumen de una versión anterior y cambió `init.sql`, reinicia la base para que aplique la migración: `docker compose restart db`. El script es idempotente y no borra datos.

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
dotnet user-secrets set "Seguridad:ClaveMaestra" "<32 bytes en Base64>" --project src/Pedidos.Api
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

| Correo | Contraseña | Rol | 2FA | Puede |
|---|---|---|---|---|
| `vendedor@pedidos.local` | `Vendedor123!` | VENDEDOR | Google Authenticator | Vender desde el catálogo (factura a un cliente o CF), clientes y **sus** ventas |
| `admin@pedidos.local` | `AdminPedidos2026!` | ADMIN | Google Authenticator | Todos los módulos, usuarios y bitácora; no vende |
| `bodega@pedidos.local` | `BodegaPedidos2026!` | BODEGA | Google Authenticator | Productos, existencias, ajustes, kardex y recepción de compras |
| `compras@pedidos.local` | `ComprasPedidos2026!` | COMPRAS | Google Authenticator | Proveedores y órdenes de compra (crear y anular) |
| `contador@pedidos.local` | `ContadorPedidos2026!` | CONTADOR | Google Authenticator | Catálogo de cuentas, partidas, libro mayor y estados financieros; consulta ventas, inventario y compras |

El 2FA es obligatorio para todos: se configura con un QR en el primer ingreso.

**Cómo entrar la primera vez (cualquier rol):** instala **Google Authenticator** en tu teléfono (gratis en Play Store o App Store). Después de la contraseña, el sistema muestra un **código QR**: escanéalo con la app (o escribe la clave que aparece debajo) y escribe el código de 6 dígitos que muestra la app. Al activarse aparecen **10 códigos de respaldo**: guárdalos, sirven si pierdes el teléfono. Desde entonces, cada inicio de sesión pide el código de la app (salvo que marques "Confiar en este dispositivo por 30 días").

Productos semilla: 5, entre ellos el **Monitor 27" con stock 1**, para probar la concurrencia, y la **Webcam HD con stock 0**, que aparece deshabilitada en el catálogo.
Son credenciales de prueba y están guardadas como hash BCrypt en `init.sql`. La contraseña del vendedor es anterior a la política nueva: si se cambia, la nueva debe cumplirla.

---

## 3. Cómo probar la API

- **Colección `.http`:** [`backend/src/Pedidos.Api/Pedidos.Api.http`](backend/src/Pedidos.Api/Pedidos.Api.http) trae 14 casos (login, catálogo, pedido feliz, 400, 401, 403 y 404). Se ejecuta con VS Code + REST Client, o directamente en Visual Studio o Rider. El token se encadena solo entre peticiones.
- **Swagger:** http://localhost:5080/swagger (solo en entorno Development).
- **curl** (Git Bash, Linux o macOS):

```bash
# Login en dos pasos (2FA obligatorio). Paso 1: correo y contraseña devuelven un desafío
# (en el primer ingreso también "uri"/"secreto" para registrar la cuenta en Google Authenticator).
DESAFIO=$(curl -s -X POST http://localhost:5080/api/auth/login -H "Content-Type: application/json" \
  -d '{"email":"vendedor@pedidos.local","password":"Vendedor123!"}' | sed -E 's/.*"desafio":"([^"]+)".*/\1/')
# Paso 2: el código de 6 dígitos de la app devuelve el token.
TOKEN=$(curl -s -X POST http://localhost:5080/api/auth/login/verificar -H "Content-Type: application/json" \
  -d "{\"desafio\":\"$DESAFIO\",\"codigo\":\"<código de Google Authenticator>\"}" | sed -E 's/.*"token":"([^"]+)".*/\1/')

# Recuperación de contraseña: el enlace llega a la bandeja de Mailpit
curl -s -X POST http://localhost:5080/api/auth/recuperar -H "Content-Type: application/json" -d '{"email":"vendedor@pedidos.local"}'

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
| POST | `/api/auth/login` | Público (10 intentos/min por IP) | 200 `{ token, expiraEn, username, email, rol }` o, con 2FA, 200 `{ requiereSegundoFactor: true, desafio, metodo, destino }` · 400 · 401 · 429 |
| POST | `/api/auth/login/verificar` | Público (con el desafío) | 200 sesión (+ `tokenDispositivo` si se pidió confiar en el dispositivo) · 401 código incorrecto · 400 desafío vencido |
| POST | `/api/auth/recuperar` | Público (5 cada 15 min por IP) | 202, siempre la misma respuesta (no revela si el correo existe) |
| POST | `/api/auth/restablecer` | Público (con el token del correo) | 200 · 400 enlace vencido o usado, o contraseña que no cumple la política |
| GET/POST | `/api/cuenta/...` | Autenticado | Estado de seguridad, cambio de contraseña, activar/desactivar Google Authenticator, códigos de respaldo, accesos propios |
| GET | `/api/admin/bitacora` | ADMIN | Últimos 100 eventos de seguridad de todos los usuarios |
| GET/POST/PUT/DELETE | `/api/admin/usuarios[/{id}]` | ADMIN | Listar (`?buscar=`), crear (envía invitación), editar, `/activar`, `/desactivar`, `/invitacion`, eliminar (solo sin pedidos) · 400 validación · 403 no admin · 404 |
| GET | `/api/productos` | Autenticado | 200 `[{ id, codigo, nombre, precio, stock, marca, categoria }]` (solo productos activos) · 401 |
| GET | `/api/productos/{id}` | Autenticado | Ficha del producto: descripción, garantía, especificaciones e ids de sus fotos · 404 |
| GET | `/api/productos/{id}/imagenes/{imagenId}` | **Público** | La foto (JPG/PNG/WebP), con caché de 7 días · 404 |
| DELETE | `/api/inventario/productos/{id}` | BODEGA, ADMIN | 204 · 400 si tiene ventas, compras o movimientos (hay que desactivarlo) |
| POST/DELETE | `/api/inventario/productos/{id}/imagenes[/{imagenId}]` | BODEGA, ADMIN | Subir (multipart, campo `archivo`, hasta 2 MB y 5 por producto) o eliminar una foto; `POST .../{imagenId}/principal` la pone primera |
| POST | `/api/pedidos` | VENDEDOR | 201 `{ numero, fecha, usuarioId, total, lineas[], serie, autorizacion, clienteNit, baseImponible, iva, ... }` · 400 · 401 · 403. Acepta `clienteId` (sin él: CF), `formaPago` (`EFECTIVO`, `TARJETA`, `TRANSFERENCIA`) y la entrega: `direccionEntrega`, `departamento` y `municipio` (validados contra `/api/geografia`) |
| GET | `/api/geografia` | Autenticado | Los 22 departamentos de Guatemala con sus 340 municipios (para los selectores) |
| GET | `/api/pipeline` | VENDEDOR (las suyas), ADMIN, CONTADOR, BODEGA | Tablero por etapas; cada tarjeta dice a qué etapa puede llevarla el usuario |
| GET | `/api/pipeline/{id}` | Igual | Venta con su entrega e historial de etapas |
| POST | `/api/pipeline/{id}/avanzar` | Según la etapa | `{ nota? }` → siguiente etapa · 400 si al rol no le toca o ya está entregada |
| GET | `/api/pedidos?desde=&hasta=` | VENDEDOR (las suyas), ADMIN, CONTADOR | Facturas del rango (por defecto, el mes) |
| GET | `/api/pedidos/{id}` | Dueño, ADMIN o CONTADOR | 200 · 401 · 404 |
| GET/POST/PUT | `/api/clientes[/{id}]` | VENDEDOR, ADMIN | Buscar (`?buscar=` NIT o nombre), crear y editar · 400 NIT inválido o repetido |
| GET/POST/PUT | `/api/inventario/productos[/{id}]` | Consulta: BODEGA, ADMIN, COMPRAS, CONTADOR · cambios: BODEGA, ADMIN | Existencias valorizadas (`?bajoMinimo=true`), alta y edición de productos |
| GET | `/api/inventario/productos/{id}/kardex` | Igual que la consulta | Movimientos con saldo y costo promedio |
| POST | `/api/inventario/ajustes` | BODEGA, ADMIN | Entrada o salida con motivo · 400 si no alcanza la existencia |
| GET/POST/PUT | `/api/compras/proveedores[/{id}]` | Consulta: BODEGA, COMPRAS, ADMIN, CONTADOR · cambios: COMPRAS, ADMIN | Proveedores con NIT validado |
| GET/POST | `/api/compras/ordenes[/{id}]` | Consulta: igual · crear: COMPRAS, ADMIN | Órdenes de compra (`?estado=PENDIENTE`) |
| POST | `/api/compras/ordenes/{id}/recibir` | BODEGA, COMPRAS, ADMIN | `{ facturaProveedor }` → entra al inventario y se paga · 400 si ya no está pendiente |
| POST | `/api/compras/ordenes/{id}/anular` | COMPRAS, ADMIN | Solo órdenes pendientes |
| GET/POST/PUT | `/api/contabilidad/cuentas[/{id}]` | CONTADOR, ADMIN | Catálogo con saldos; las cuentas del sistema no se desactivan |
| GET/POST | `/api/contabilidad/partidas[/{id}]` | CONTADOR, ADMIN | Libro diario (`?desde=&hasta=&origen=`) y partidas manuales · 400 si no cuadran |
| GET | `/api/contabilidad/reportes/{mayor/{cuentaId} \| balance-comprobacion \| estado-resultados \| balance-general}` | CONTADOR, ADMIN | Libro mayor y estados financieros (`?desde=&hasta=`; balance general `?al=`) |
| GET | `/api/panel` | ADMIN, BODEGA, COMPRAS, CONTADOR | Indicadores del inicio |
| GET | `/api/reportes/ventas?desde=&hasta=` | VENDEDOR (las suyas), ADMIN, CONTADOR | Resumen con utilidad, margen y ticket promedio, comparación con el período anterior, y ventas por día, producto, categoría, vendedor, cliente y forma de pago |

Todos los errores tienen el mismo formato: `{ "error": "mensaje legible" }`.

### Pruebas automatizadas

```bash
cd backend && dotnet test      # 162 pruebas (1 se omite si no hay SQL Server; ver abajo)
cd frontend && flutter test    # 210 pruebas
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
| Fotos de producto incluidas como *assets* (`frontend/assets/productos`), elegidas según el tipo de producto (teclado, mouse, monitor...), con ícono genérico como respaldo. | Sin dependencia de un servicio externo de imágenes en tiempo de ejecución. Son fotos de Wikimedia Commons con licencia libre; autor y licencia de cada una en [`CREDITOS.md`](frontend/assets/productos/CREDITOS.md). |

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

### Endurecimiento adicional

| Amenaza | Defensa | Dónde |
|---|---|---|
| **Inyección SQL** | Consultas parametrizadas (EF Core). Tipos estrictos en el JSON: `"productoId": "1 OR 1=1"` se rechaza con 400 antes de llegar a la BD. Login de BD de mínimos privilegios (sin `DROP`/`ALTER`). | `AuthService`, `PedidoService`, `init.sql`; pruebas con cargas `' OR '1'='1`, `'; DROP TABLE ...` y `UNION SELECT` |
| **Fuerza bruta en el login** | 10 intentos/min por IP, **más** bloqueo de 5 min por cuenta tras 5 fallos (frena ataques distribuidos desde muchas IPs). Cuenta también usuarios inexistentes, así que no revela cuáles existen. | `RateLimitPolicies`, `LoginThrottle` |
| **Flood / DoS a nivel de aplicación** | Límite global de 300 peticiones/min por IP; límite de 20 pedidos/min por usuario (token bucket); `429` con `Retry-After`. | `Program.cs`, `RateLimitPolicies` |
| **Agotamiento de recursos** | Kestrel: cuerpo máximo 32 KB (413), cabeceras 16 KB, timeout de cabeceras de 10 s (*slowloris*), máximo 500 conexiones. Topes de entrada: 50 líneas por pedido, 1000 unidades por línea, usuario ≤ 50 y contraseña ≤ 128 caracteres. Timeout de comandos SQL de 15 s. Caché del bloqueo con tamaño máximo. | `Program.cs`, `InputLimits` |
| **Flood al frontend** | nginx: 20 peticiones/s por IP (ráfaga 60), 30 conexiones por IP, timeouts cortos, cuerpo máximo 1 KB, solo `GET`/`HEAD`. | `frontend/nginx.conf` |
| **XSS / clickjacking** | CSP estricta en el frontend (solo código propio; conexiones solo a sí mismo y a la API, así un script inyectado no podría enviar el token a otro dominio). `X-Frame-Options: DENY`, `nosniff`, `Referrer-Policy`, `Permissions-Policy`. En la API: `default-src 'none'` y `Cache-Control: no-store`. | `nginx.conf`, `SecurityHeaders` |
| **Divulgación de información** | Sin cabecera `Server` ni `server_tokens`; errores genéricos; logs de intentos fallidos sin contraseñas y sin caracteres de control (evita falsificar líneas del log). | `Program.cs`, `AuthController` |
| **Compromiso de un contenedor** | API y frontend con sistema de archivos de solo lectura, `cap_drop: ALL`, `no-new-privileges`, usuario no root y límites de memoria, CPU y procesos. La BD no expone su puerto. | `docker-compose.yml` |

Verificado contra el stack en Docker:
- el flood de 400 peticiones terminó con 429 por encima del límite, y la API siguió respondiendo con 1 % de CPU;
- el cuerpo de 88 KB devolvió 413;
- la cuenta quedó bloqueada tras 5 fallos, aun con la contraseña correcta;
- las inyecciones SQL devolvieron 401;
- un `POST` a nginx devolvió 405.

> **Sobre DDoS:** un ataque distribuido real (miles de IPs, gigabits de tráfico) no se frena dentro de la aplicación: satura la red antes de llegar a ella. En producción se mitiga en el borde (Cloudflare, AWS Shield/WAF, Azure Front Door o el balanceador) con filtrado y límites por IP. Lo implementado aquí evita que un solo cliente o una ráfaga agote los recursos de la API y la base de datos. Si la API se publica detrás de un proxy, hay que configurar `ForwardedHeaders` con la IP del proxy como confiable, para que los límites se apliquen a la IP real del cliente.

---

## 5 bis. Login de ERP (fuera del alcance del PDF)

Extensión opcional. Todas las piezas son gratuitas y funcionan con `docker compose up`, sin cuentas externas.

| Función | Cómo funciona | Por qué así |
|---|---|---|
| **Inicio de sesión con correo** | El correo se normaliza a minúsculas; mismo mensaje genérico si el correo o la contraseña fallan. | No revela qué cuentas existen. |
| **2FA con Google Authenticator (TOTP, RFC 6238)** | QR generado en el navegador (`qr_flutter`) y verificación con Otp.NET. Tolera ±30 s de desfase de reloj y **rechaza reutilizar** un código ya aceptado. | Estándar abierto y gratuito, funciona sin conexión y no depende de redes de telefonía (evita el robo de SMS por *SIM swapping*). |
| **Configuración obligatoria en el primer ingreso** | Ningún usuario (vendedor o administrador) puede entrar sin la app hasta configurarla: tras la contraseña, el login devuelve el QR (método `CONFIGURAR`) y el primer código de la app activa el 2FA y abre la sesión. | El 2FA obligatorio no depende de que el usuario "se acuerde" de activarlo. |
| **Códigos de respaldo** | 10 códigos `XXXXX-XXXXX` de un solo uso. Se muestran una vez y se guardan solo como HMAC. | Si el usuario pierde el teléfono no queda fuera de su cuenta. |
| **Desafío de 2FA** | Tras la contraseña se emite un JWT de 5 minutos con **otra audiencia**, que nunca sirve como sesión. Máximo 5 códigos por desafío, un solo uso, y se invalida si la contraseña cambia. | La contraseña correcta sola no da acceso. |
| **"Confiar en este dispositivo"** | Token aleatorio de 30 días en `flutter_secure_storage`; en la BD solo su HMAC. Se revoca al cambiar la contraseña. | Menos fricción sin perder control. |
| **2FA obligatorio para todos** | Nadie puede desactivarlo; solo reconfigurarlo en otro teléfono. | Todas las cuentas quedan protegidas aunque se filtre una contraseña. |
| **Recuperación de contraseña** | Enlace de un solo uso que vence en 30 min. Pedir uno nuevo invalida el anterior. La respuesta es idéntica exista o no el correo, y el envío va por una cola en segundo plano, así que el tiempo tampoco lo delata. | Buenas prácticas de OWASP para restablecer contraseñas. |
| **Cierre de sesiones al cambiar la contraseña** | El JWT lleva una "versión de sesión"; al restablecer o cambiar la contraseña (o desactivar el 2FA) sube la versión y los tokens anteriores dejan de valer. | Si la contraseña se filtró, el atacante pierde el acceso de inmediato. |
| **Política de contraseñas** | Mínimo 12 caracteres, que no contenga el correo ni sea repetitiva, y **que no esté filtrada**: consulta gratuita a *Pwned Passwords* con k-anonimato (solo se envían 5 caracteres del SHA-1). Si el servicio no responde, se permite continuar. | Lo que recomienda hoy el NIST (SP 800-63B), en lugar de reglas de composición. |
| **Aviso de dispositivo nuevo** | Correo cuando se inicia sesión desde un navegador o sistema no visto antes para ese usuario. | El usuario detecta accesos que no reconoce. |
| **Bitácora de accesos** | Registra logins, fallos, bloqueos, 2FA, recuperaciones y cambios de seguridad, con IP y dispositivo. El usuario ve su actividad y el ADMIN ve la de todos. | Auditoría. |
| **Secretos cifrados** | El secreto TOTP se guarda con AES-256-GCM. Claves derivadas por HKDF de `SEGURIDAD_CLAVE_MAESTRA`. | Una copia filtrada de la BD no permite generar códigos. |
| **Aviso de Bloq Mayús y "recordar mi correo"** | Solo en el frontend; nunca se guarda la contraseña. | Comodidad. |
| **Administración de usuarios (solo ADMIN)** | Nombre, apellido, teléfono (8 dígitos de Guatemala; se guarda como `+502XXXXXXXX`), correo y código corporativo únicos, rol y estado. **El administrador no define contraseñas:** al crear el usuario se envía una invitación de 48 h para que la cree él mismo. Desactivar corta sus sesiones al instante. Un usuario con pedidos no se elimina, se desactiva. El admin no puede desactivarse ni eliminarse a sí mismo y siempre queda al menos un administrador activo. Todo usuario nuevo configura Google Authenticator en su primer ingreso. | Separación de funciones y trazabilidad: cada alta, cambio o baja queda en la bitácora con el administrador que la hizo. |

---

## 5 ter. ERP: ventas, inventario, compras y contabilidad (fuera del alcance del PDF)

Cada rol ve solo sus módulos (menú **Módulos** en la barra superior). El vendedor empieza en el catálogo; los demás, en un **panel** con ventas del día y del mes, utilidad bruta, valor del inventario, órdenes pendientes y productos por reabastecer.

| Módulo | Qué hace | Reglas importantes |
|---|---|---|
| **Ventas** | Venta de contado a un cliente (NIT) o a consumidor final (CF), con **factura simulada** (serie A, número y autorización). | Precios con **IVA 12 % incluido**: el sistema separa la base y el IVA y la suma siempre da el total exacto. Forma de pago: efectivo (Caja) o tarjeta/transferencia (Bancos). |
| **Clientes y proveedores** | Altas, búsqueda por NIT o nombre, activar o desactivar. | El **NIT se valida con su dígito verificador** (módulo 11; el 10 se escribe K) y es único. "CF" es del sistema. |
| **Entrega y pipeline** | Cada venta lleva dirección, **departamento y municipio** (selectores; el municipio depende del departamento) y pasa por etapas: **Nuevo → Revisado → Autorizado → Despachado → En camino → Entregado/cobrado**. Tablero tipo kanban con el botón de la siguiente etapa, línea de tiempo en el detalle y alerta de ventas con 2 o más días en una etapa. | Cada etapa la mueve su rol: el vendedor revisa (solo las suyas), administración o contabilidad autoriza y bodega despacha, envía y entrega. Solo se avanza un paso a la vez, con cambio condicional (dos personas no la mueven a la vez) y queda historial con quién, cuándo y una nota. |
| **Mapa de ventas** | En Reportes de ventas: mapa de Guatemala coloreado por ventas de cada departamento; al pasar el mouse o tocar uno muestra ventas, facturas, unidades y el **producto más vendido** ahí. También la distribución de las ventas por etapa. | Límites de geoBoundaries / OpenStreetMap (ODbL, créditos en `frontend/assets/mapas/CREDITOS.md`). |
| **Reportes de ventas** | Ventas, facturas, ticket promedio, utilidad bruta y margen, IVA cobrado; variación contra el período anterior; ventas por día; ranking por producto, categoría, vendedor, cliente y forma de pago con su participación. Períodos rápidos: hoy, semana, mes, mes anterior y año. | El vendedor ve solo sus ventas. La utilidad se calcula sin IVA con el costo promedio de cada venta. |
| **Productos (CRUD) y fotos** | Alta, edición de la ficha, hasta **5 fotos** por producto (subir, elegir la principal, eliminar), activar/desactivar y eliminar. En la ficha, las fotos se ven en un **carrusel** que avanza solo (se pausa con el mouse encima; flechas, puntos y miniaturas). El catálogo abre con un carrusel de **destacados**. | El formato se valida por la firma de los bytes (no por la extensión). Solo se elimina un producto sin ventas, compras ni movimientos; si ya tiene historia se desactiva. Las 25 fotos de ejemplo son de Wikimedia Commons con licencias libres (créditos en `db/init/imagenes/CREDITOS.md`). |
| **Ficha del producto** | Marca, categoría, descripción detallada (con párrafos), garantía y especificaciones técnicas. En el catálogo, tocar la foto o el nombre abre la ficha; también se filtra por categoría. | Se edita desde Inventario (BODEGA/ADMIN). Hasta 2000 caracteres de descripción y 20 especificaciones sin nombres repetidos. |
| **Inventario** | Productos, existencias valorizadas, stock mínimo, **kardex** y ajustes (conteo físico, daño, sobrante). | **Costo promedio ponderado**: cada entrada lo recalcula en el mismo `UPDATE` que suma la existencia, así dos operaciones simultáneas no dejan un costo incorrecto. La existencia solo cambia con movimientos: no se edita a mano. |
| **Compras** | Órdenes de compra a proveedores (costos sin IVA) → **recepción en bodega** con la factura del proveedor → pago de contado desde Bancos. | La recepción es condicional (`WHERE Estado = 'PENDIENTE'`): si dos personas reciben la misma orden a la vez, solo una lo logra y el inventario no se duplica. |
| **Contabilidad** | Catálogo de cuentas, **libro diario**, partidas manuales, **libro mayor**, balance de comprobación, estado de resultados y balance general. | Cada venta, compra y ajuste genera su **partida automática en la misma transacción**: si algo falla no queda nada a medias. Toda partida debe cuadrar (debe = haber); la BD además impide líneas con debe y haber a la vez. |

**Partidas automáticas**

| Operación | Debe | Haber |
|---|---|---|
| Venta | Caja o Bancos (total) · Costo de ventas (costo) | Ventas (base sin IVA) · IVA por pagar · Inventario (costo) |
| Recepción de compra | Inventario (subtotal) · IVA por cobrar | Bancos (total) |
| Ajuste de salida | Faltantes y mermas de inventario | Inventario |
| Ajuste de entrada | Inventario | Otros ingresos |

**Apertura.** Al migrar, `init.sql` da un costo inicial a los productos que no lo tienen, registra la existencia en el kardex (`INICIAL`) y crea la **partida de apertura** (Q100,000 en Bancos más el inventario, contra Capital). Así inventario y contabilidad arrancan cuadrados. Las ventas anteriores al ERP quedan asignadas a CF y sin partida.

**Datos de demostración.** Con `DEMO_GENERAR=true` (valor por defecto en Docker), la API genera al arrancar por primera vez 20 productos más, 24 clientes repartidos por el país, 3 vendedores y **120 días de operación**: compras semanales recibidas en bodega, unas 750 ventas con entrega, su avance por el pipeline, gastos fijos mensuales y depósitos semanales. Todo se registra con los mismos servicios de la app, así que inventario, kardex y contabilidad quedan cuadrados. Tarda 1 a 2 minutos en segundo plano y no se repite (busca el producto `P-006`). Los vendedores generados no tienen contraseña: el administrador puede enviarles la invitación.

**Probarlo:**
1. Entra como **compras** y crea una orden.
2. Entra como **bodega** y recíbela: mira el kardex y el nuevo costo promedio.
3. Entra como **vendedor**, vende a un cliente con NIT y revisa la factura.
4. Entra como **contador**: la venta y la compra ya están en el libro diario, y el balance general cuadra.

## 6. Pendiente y posibles mejoras

| Tema | Estado y cómo se resolvería |
|---|---|
| HTTPS | Compose expone HTTP porque es un entorno local. En producción, TLS se termina en un reverse proxy o balanceador (nginx, Traefik o un load balancer gestionado), con HSTS y `API_URL=https://...`. |
| Token en web | `flutter_secure_storage` en web cifra con WebCrypto, pero la clave también vive en el navegador, así que un XSS podría leerlo. En producción: cookie `HttpOnly; Secure; SameSite=Strict` emitida por el backend (o un BFF), más una CSP estricta. |
| Refresh tokens / revocación | Hoy el token dura 60 min y cerrar sesión solo lo borra del cliente. Se agregaría un refresh token rotativo guardado en BD y una lista de revocación (`jti`). |
| Idempotencia al crear pedidos | El doble clic está cubierto en la UI. Para reintentos de red, el cliente enviaría un `Idempotency-Key` y la API guardaría la respuesta asociada a esa clave. |
| Migraciones | El esquema lo gestiona `init.sql`. Con evolución del modelo se pasaría a migraciones versionadas (EF Core Migrations o DbUp). |
| Rate limit distribuido | Los límites y el bloqueo de cuentas son en memoria (por instancia). Con varias réplicas irían en Redis o en el gateway. |
| Observabilidad | Logs estructurados y *health checks* de dependencias (`/health` hoy no consulta la BD). |
| Paginación del catálogo | No hace falta con 5 productos; con catálogos grandes: `?page=&size=` y búsqueda. |
| ERP: anular ventas | Hoy una factura no se anula. Se haría con una nota de crédito que devuelva la existencia y registre la partida inversa. |
| ERP: crédito | Ventas y compras son de contado. Al crédito se agregarían cuentas por cobrar y por pagar, abonos y antigüedad de saldos. |
| ERP: FEL real | La factura es una simulación. En producción se certificaría con un certificador autorizado por la SAT (XML firmado, UUID oficial). |
| ERP: cierre contable | No hay cierre de período: el resultado del ejercicio se acumula en el balance general. Se agregaría el cierre mensual o anual, que traslada la utilidad a resultados acumulados y bloquea el período. |
| ERP: recepción parcial | Una orden se recibe completa. Para recibirla por partes haría falta registrar la cantidad recibida por línea. |

---

## 7. Uso de asistentes de IA

Se utilizó **Claude Code (Anthropic)** como asistente durante toda la prueba, para:

- instalar y verificar el entorno (.NET 8, Flutter, Docker);
- generar el código del backend, del frontend y de Docker, y los scripts SQL;
- escribir y ejecutar las pruebas automatizadas y las pruebas manuales de punta a punta (API con curl y la app en el navegador);
- redactar SECURITY_REVIEW.md, MENSAJE_PM.md y este README.

Las decisiones de diseño se revisaron y validaron ejecutando el sistema: reglas de negocio, concurrencia con peticiones simultáneas reales, flujo 401 → login y ausencia del token en consola y almacenamiento.
# prueba_csi
