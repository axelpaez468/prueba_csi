using System.Net;
using System.Text.Json;
using Pedidos.Api.Domain;
using Pedidos.Tests.Infra;

namespace Pedidos.Tests.Http;

/// <summary>
/// Procesos completos por HTTP, como los haría cada área desde la app: cada paso con el rol que le toca y
/// verificando lo que debe quedar en inventario, contabilidad y reportes.
/// </summary>
[Collection(ApiColeccion.Nombre)]
public class FlujosHttpTests(ApiEnVivo api)
{
    private static string Hoy => DateTime.UtcNow.AddHours(-6).ToString("yyyy-MM-dd");

    /// <summary>Producto nuevo con existencia (lo crea bodega y le da entrada a un costo).</summary>
    private async Task<int> ProductoConStock(int stock, decimal costo = 50m, decimal precio = 112m)
    {
        using var bodega = await api.ComoAsync(Roles.Bodega);
        var codigo = "T-" + Guid.NewGuid().ToString("N")[..8].ToUpperInvariant();
        var p = await bodega.PostJson("api/inventario/productos", new { codigo, nombre = $"Producto {codigo}", precio, stockMinimo = 1 }).Creado();
        if (stock > 0)
            await bodega.PostJson("api/inventario/ajustes",
                new { productoId = p.Int("id"), tipo = "ENTRADA", cantidad = stock, costoUnitario = costo, motivo = "Existencia inicial de prueba" }).Creado();
        return p.Int("id");
    }

    private async Task<JsonElement> Producto(int id)
    {
        using var bodega = await api.ComoAsync(Roles.Bodega);
        return (await bodega.GetAsync($"api/inventario/productos/{id}/kardex").Ok()).GetProperty("producto");
    }

    private async Task<JsonElement> BalanceDeComprobacion()
    {
        using var contador = await api.ComoAsync(Roles.Contador);
        // El reporte admite hasta un año; todo lo de las pruebas es de hoy.
        return await contador.GetAsync($"api/contabilidad/reportes/balance-comprobacion?desde={Hoy}&hasta={Hoy}").Ok();
    }

    [ApiFact]
    public async Task Venta_DeInicioAFin_PorElPipeline_ConInventarioContabilidadYReportes()
    {
        var producto = await ProductoConStock(10, costo: 50m, precio: 112m);
        using var vendedor = await api.ComoNuevoAsync(Roles.Vendedor);

        // 1. Cliente con NIT y venta con entrega.
        var cliente = await vendedor.PostJson("api/clientes", new { nit = EntradasHttpTests.NitValido(), nombre = "Comercial La Prueba" }).Creado();
        var venta = await vendedor.PostJson("api/pedidos", new
        {
            lineas = new[] { new { productoId = producto, cantidad = 3 } },
            clienteId = cliente.Int("id"), formaPago = "TRANSFERENCIA",
            direccionEntrega = "4a. calle 5-10 zona 1", departamento = "Quetzaltenango", municipio = "Coatepeque"
        }).Creado();
        var numero = venta.Int("numero");

        Assert.Equal(336m, venta.Dec("total"));                              // 3 × 112 con IVA
        Assert.Equal(300m, venta.Dec("baseImponible"));
        Assert.Equal(36m, venta.Dec("iva"));
        Assert.Equal(EstadosVenta.Nuevo, venta.Str("estado"));
        Assert.Equal(7, (await Producto(producto)).Int("stock"));            // salió del inventario

        // 2. Cada área mueve su etapa; nadie se salta la suya.
        using var contador = await api.ComoAsync(Roles.Contador);
        using var bodega = await api.ComoAsync(Roles.Bodega);
        await contador.PostJson($"api/pipeline/{numero}/avanzar").Esperar(HttpStatusCode.BadRequest); // aún no está revisada
        await vendedor.PostJson($"api/pipeline/{numero}/avanzar", new { nota = "Datos confirmados con el cliente" }).Ok();
        await bodega.PostJson($"api/pipeline/{numero}/avanzar").Esperar(HttpStatusCode.BadRequest);    // falta autorizar
        await contador.PostJson($"api/pipeline/{numero}/avanzar").Ok();
        await vendedor.PostJson($"api/pipeline/{numero}/avanzar").Esperar(HttpStatusCode.BadRequest);  // despachar no le toca
        foreach (var _ in new[] { "DESPACHADO", "EN_CAMINO", "ENTREGADO" })
            await bodega.PostJson($"api/pipeline/{numero}/avanzar").Ok();
        await bodega.PostJson($"api/pipeline/{numero}/avanzar").Rechazo("entregada");

        var detalle = await vendedor.GetAsync($"api/pedidos/{numero}").Ok();
        Assert.Equal(EstadosVenta.Entregado, detalle.Str("estado"));
        Assert.Equal(EstadosVenta.Orden, detalle.GetProperty("historial").EnumerateArray().Select(h => h.Str("estado")));
        Assert.Equal("Datos confirmados con el cliente", detalle.GetProperty("historial")[1].Str("nota"));

        // 3. Contabilidad: la venta generó su partida, y todo el libro cuadra.
        var partidas = await contador.GetAsync($"api/contabilidad/partidas?desde={Hoy}&hasta={Hoy}&origen=VENTA").Ok();
        var deLaVenta = partidas.EnumerateArray().Single(p => p.TryGetProperty("referenciaId", out var r) && r.ValueKind == JsonValueKind.Number && r.GetInt64() == numero);
        var lineas = deLaVenta.GetProperty("lineas").EnumerateArray().ToList();
        Assert.Equal(lineas.Sum(l => l.Dec("debe")), lineas.Sum(l => l.Dec("haber")));
        Assert.Contains(lineas, l => l.Dec("haber") == 36m);    // IVA por pagar
        Assert.Contains(lineas, l => l.Dec("debe") == 150m);    // costo de ventas: 3 × 50
        var balance = await BalanceDeComprobacion();
        Assert.True(balance.GetProperty("cuadra").GetBoolean());
        Assert.Equal(balance.Dec("totalDebe"), balance.Dec("totalHaber"));

        // 4. Reportes: la venta cuenta como cerrada en el pronóstico y aparece en el reporte del vendedor.
        var pronostico = await vendedor.GetAsync($"api/reportes/pronostico?desde={Hoy}&hasta={Hoy}").Ok();
        Assert.True(pronostico.Dec("cerrado") >= 336m);
        var reporte = await vendedor.GetAsync($"api/reportes/ventas?desde={Hoy}&hasta={Hoy}").Ok();
        Assert.Contains(reporte.GetProperty("porDepartamento").EnumerateArray(), d => d.Str("departamento") == "Quetzaltenango");
    }

    [ApiFact]
    public async Task UnVendedor_NoVeNiMueveLasVentasDeOtro()
    {
        var producto = await ProductoConStock(2);
        using var vendedor = await api.ComoNuevoAsync(Roles.Vendedor);
        var numero = (await vendedor.PostJson("api/pedidos", new { lineas = new[] { new { productoId = producto, cantidad = 1 } } }).Creado()).Int("numero");

        var (_, email) = await api.CrearUsuarioAsync(Roles.Vendedor);
        using var otro = api.Cliente(await api.EntrarAsync(email, TestDb.PasswordDePrueba));

        Assert.Equal(HttpStatusCode.NotFound, (await otro.GetAsync($"api/pedidos/{numero}")).StatusCode);
        Assert.Equal(HttpStatusCode.NotFound, (await otro.GetAsync($"api/pipeline/{numero}")).StatusCode);
        var avanzar = await otro.PostJson($"api/pipeline/{numero}/avanzar");
        Assert.True(avanzar.StatusCode is HttpStatusCode.NotFound or HttpStatusCode.BadRequest, $"{(int)avanzar.StatusCode}");
        var suyas = await otro.GetAsync("api/pedidos").Ok();
        Assert.DoesNotContain(suyas.EnumerateArray(), p => p.Int("numero") == numero);
        var tablero = await otro.GetAsync("api/pipeline").Ok();
        Assert.DoesNotContain(tablero.EnumerateArray(), p => p.Int("numero") == numero);
        var reporte = await otro.GetAsync($"api/reportes/pronostico?desde={Hoy}&hasta={Hoy}").Ok();
        Assert.Equal(0m, reporte.Dec("pronostico"));

        // El vendedor dueño sí sigue en etapa NUEVO (el intento del otro no la movió).
        Assert.Equal(EstadosVenta.Nuevo, (await vendedor.GetAsync($"api/pedidos/{numero}").Ok()).Str("estado"));
    }

    [ApiFact]
    public async Task Compra_DeInicioAFin_RecalculaElCostoPromedio_YNoSeRecibeDosVeces()
    {
        var producto = await ProductoConStock(10, costo: 50m);
        using var compras = await api.ComoAsync(Roles.Compras);
        using var bodega = await api.ComoAsync(Roles.Bodega);

        var proveedor = await compras.PostJson("api/compras/proveedores", new { nit = EntradasHttpTests.NitValido(), nombre = "Proveedor de Prueba, S.A." }).Creado();
        var orden = await compras.PostJson("api/compras/ordenes", new
        {
            proveedorId = proveedor.Int("id"), lineas = new[] { new { productoId = producto, cantidad = 10, costoUnitario = 70m } }
        }).Creado();
        var numero = orden.Int("numero");
        Assert.Equal(10, (await Producto(producto)).Int("stock")); // crear la orden no mueve inventario

        await bodega.PostJson($"api/compras/ordenes/{numero}/recibir", new { facturaProveedor = "" }).Esperar(HttpStatusCode.BadRequest);
        await bodega.PostJson($"api/compras/ordenes/{numero}/recibir", new { facturaProveedor = "FAC-A-1234" }).Ok();

        var p = await Producto(producto);
        Assert.Equal(20, p.Int("stock"));
        Assert.Equal(60m, p.Dec("costoPromedio")); // (10×50 + 10×70) / 20

        await bodega.PostJson($"api/compras/ordenes/{numero}/recibir", new { facturaProveedor = "FAC-A-1234" }).Esperar(HttpStatusCode.BadRequest);
        await compras.PostJson($"api/compras/ordenes/{numero}/anular").Esperar(HttpStatusCode.BadRequest);
        Assert.Equal(20, (await Producto(producto)).Int("stock"));
        Assert.True((await BalanceDeComprobacion()).GetProperty("cuadra").GetBoolean());
    }

    [ApiFact]
    public async Task OrdenAnulada_NoSePuedeRecibir()
    {
        var producto = await ProductoConStock(0);
        using var compras = await api.ComoAsync(Roles.Compras);
        var proveedor = await compras.PostJson("api/compras/proveedores", new { nit = EntradasHttpTests.NitValido(), nombre = "Proveedor Anulado" }).Creado();
        var numero = (await compras.PostJson("api/compras/ordenes", new
        {
            proveedorId = proveedor.Int("id"), lineas = new[] { new { productoId = producto, cantidad = 5, costoUnitario = 10m } }
        }).Creado()).Int("numero");

        await compras.PostJson($"api/compras/ordenes/{numero}/anular").Ok();
        using var bodega = await api.ComoAsync(Roles.Bodega);
        await bodega.PostJson($"api/compras/ordenes/{numero}/recibir", new { facturaProveedor = "FAC-9" }).Esperar(HttpStatusCode.BadRequest);
        Assert.Equal(0, (await Producto(producto)).Int("stock"));
    }

    [ApiFact]
    public async Task VenderMasDeLoQueHay_SeRechaza_SinTocarNada()
    {
        var producto = await ProductoConStock(2);
        using var vendedor = await api.ComoNuevoAsync(Roles.Vendedor);
        var antes = (await BalanceDeComprobacion()).Dec("totalDebe");

        await vendedor.PostJson("api/pedidos", new { lineas = new[] { new { productoId = producto, cantidad = 3 } } }).Rechazo("");

        Assert.Equal(2, (await Producto(producto)).Int("stock"));
        Assert.Equal(antes, (await BalanceDeComprobacion()).Dec("totalDebe")); // sin partida
    }

    [ApiFact]
    public async Task ProductoInactivo_NoSeVende_YConVentasNoSeBorra()
    {
        var producto = await ProductoConStock(5);
        using var vendedor = await api.ComoNuevoAsync(Roles.Vendedor);
        using var bodega = await api.ComoAsync(Roles.Bodega);
        await vendedor.PostJson("api/pedidos", new { lineas = new[] { new { productoId = producto, cantidad = 1 } } }).Creado();

        await bodega.DeleteAsync($"api/inventario/productos/{producto}").Esperar(HttpStatusCode.BadRequest);
        var p = await Producto(producto);
        await bodega.PutJson($"api/inventario/productos/{producto}", new
        {
            nombre = p.Str("nombre"), precio = p.Dec("precio"), stockMinimo = 0, activo = false
        }).Ok();

        await vendedor.PostJson("api/pedidos", new { lineas = new[] { new { productoId = producto, cantidad = 1 } } }).Esperar(HttpStatusCode.BadRequest);
        var catalogo = await vendedor.GetAsync("api/productos").Ok();
        Assert.DoesNotContain(catalogo.EnumerateArray(), x => x.Int("id") == producto);
    }

    [ApiFact]
    public async Task AjusteDeSalida_NoDejaLaExistenciaNegativa()
    {
        var producto = await ProductoConStock(3);
        using var bodega = await api.ComoAsync(Roles.Bodega);
        await bodega.PostJson("api/inventario/ajustes", new { productoId = producto, tipo = "SALIDA", cantidad = 4, motivo = "Merma por daño" })
            .Esperar(HttpStatusCode.BadRequest);
        await bodega.PostJson("api/inventario/ajustes", new { productoId = producto, tipo = "SALIDA", cantidad = 3, motivo = "Merma por daño" }).Creado();
        Assert.Equal(0, (await Producto(producto)).Int("stock"));
        await bodega.PostJson("api/inventario/ajustes", new { productoId = producto, tipo = "SALIDA", cantidad = 1, motivo = "Merma por daño" })
            .Esperar(HttpStatusCode.BadRequest);
    }

    [ApiFact]
    public async Task PartidaManual_QueNoCuadra_SeRechaza_YLaQueCuadraSeRegistra()
    {
        using var contador = await api.ComoAsync(Roles.Contador);
        var cuentas = await contador.GetAsync("api/contabilidad/cuentas").Ok();
        int Cuenta(string codigo) => cuentas.EnumerateArray().Single(c => c.Str("codigo") == codigo).Int("id");
        var caja = Cuenta("1101");
        var bancos = Cuenta("1102");

        await contador.PostJson("api/contabilidad/partidas", new
        {
            fecha = Hoy, concepto = "Depósito de caja a bancos",
            lineas = new[] { new { cuentaId = bancos, debe = 100m, haber = 0m }, new { cuentaId = caja, debe = 0m, haber = 99.99m } }
        }).Rechazo("cuadra");
        await contador.PostJson("api/contabilidad/partidas", new
        {
            fecha = DateTime.UtcNow.AddDays(5).ToString("yyyy-MM-dd"), concepto = "Depósito con fecha futura",
            lineas = new[] { new { cuentaId = bancos, debe = 100m, haber = 0m }, new { cuentaId = caja, debe = 0m, haber = 100m } }
        }).Esperar(HttpStatusCode.BadRequest);
        await contador.PostJson("api/contabilidad/partidas", new
        {
            fecha = Hoy, concepto = "Depósito de caja a bancos",
            lineas = new[] { new { cuentaId = bancos, debe = 100m, haber = 0m }, new { cuentaId = caja, debe = 0m, haber = 100m } }
        }).Creado();
        Assert.True((await BalanceDeComprobacion()).GetProperty("cuadra").GetBoolean());
        var general = await contador.GetAsync($"api/contabilidad/reportes/balance-general?al={Hoy}").Ok();
        Assert.True(general.GetProperty("cuadra").GetBoolean());
    }

    [ApiFact]
    public async Task ClienteConNitRepetido_EnOtroFormato_SeRechaza()
    {
        using var vendedor = await api.ComoNuevoAsync(Roles.Vendedor);
        var nit = EntradasHttpTests.NitValido();
        await vendedor.PostJson("api/clientes", new { nit, nombre = "Primero" }).Creado();
        var conGuion = nit[..^1] + "-" + nit[^1];
        await vendedor.PostJson("api/clientes", new { nit = " " + conGuion + " ", nombre = "Repetido" }).Esperar(HttpStatusCode.BadRequest);
        await vendedor.PostJson("api/clientes", new { nit = nit[..^1] + ((nit[^1] - '0' + 1) % 10), nombre = "NIT inválido" })
            .Esperar(HttpStatusCode.BadRequest);
    }

    [ApiFact]
    public async Task UsuarioNuevo_RecibeLaInvitacion_CreaSuContrasena_YEntraConGoogleAuthenticator()
    {
        using var admin = await api.ComoAsync(Roles.Admin);
        var sufijo = Guid.NewGuid().ToString("N")[..6];
        var email = $"invitado.{sufijo}@pedidos.test";
        var u = await admin.PostJson("api/admin/usuarios", new
        {
            nombre = "Invitado", apellido = "De Prueba", telefono = "55551234", email, codigoCorporativo = "INV-" + sufijo.ToUpperInvariant(), rol = Roles.Vendedor
        }).Creado();
        Assert.False(u.GetProperty("tieneContrasena").GetBoolean());

        // Sin contraseña todavía no puede entrar.
        using var anonimo = api.Cliente();
        await anonimo.PostJson("api/auth/login", new { email, password = TestDb.PasswordDePrueba }).Esperar(HttpStatusCode.Unauthorized);

        var correo = await api.CorreoParaAsync(email, "Bienvenido al Sistema de Pedidos");
        Assert.NotNull(correo.HtmlBody);   // con diseño
        Assert.NotNull(correo.TextBody);   // y en texto plano
        var token = ApiEnVivo.TokenDelEnlace(correo);

        await anonimo.PostJson("api/auth/restablecer", new { token, nuevaPassword = ApiEnVivo.PasswordFiltrada }).Rechazo("filtr");
        await anonimo.PostJson("api/auth/restablecer", new { token, nuevaPassword = "corta" }).Esperar(HttpStatusCode.BadRequest);
        const string password = "Mi-clave-nueva-2026";
        await anonimo.PostJson("api/auth/restablecer", new { token, nuevaPassword = password }).Ok();
        await anonimo.PostJson("api/auth/restablecer", new { token, nuevaPassword = "Otra-clave-nueva-2026" }).Esperar(HttpStatusCode.BadRequest);

        using var nuevo = api.Cliente(await api.EntrarAsync(email, password));
        Assert.Equal(HttpStatusCode.OK, (await nuevo.GetAsync("api/productos")).StatusCode);
        Assert.Equal(HttpStatusCode.Forbidden, (await nuevo.GetAsync("api/admin/usuarios")).StatusCode);
    }

    [ApiFact]
    public async Task Recuperacion_ResponderIgualExistaONoElCorreo_YElEnlaceCierraLasSesiones()
    {
        var (_, email) = await api.CrearUsuarioAsync(Roles.Contador);
        var sesion = await api.EntrarAsync(email, TestDb.PasswordDePrueba);
        using var anonimo = api.Cliente();

        var a = await anonimo.PostJson("api/auth/recuperar", new { email }).Esperar(HttpStatusCode.Accepted);
        var b = await anonimo.PostJson("api/auth/recuperar", new { email = "no-existe@pedidos.test" }).Esperar(HttpStatusCode.Accepted);
        Assert.Equal(a.Str("mensaje"), b.Str("mensaje"));

        var token = ApiEnVivo.TokenDelEnlace(await api.CorreoParaAsync(email, "Restablece tu contraseña"));
        await anonimo.PostJson("api/auth/restablecer", new { token = token + "x", nuevaPassword = "Clave-recuperada-2026" }).Esperar(HttpStatusCode.BadRequest);
        await anonimo.PostJson("api/auth/restablecer", new { token, nuevaPassword = "Clave-recuperada-2026" }).Ok();

        using var vieja = api.Cliente(sesion);
        Assert.Equal(HttpStatusCode.Unauthorized, (await vieja.GetAsync("api/cuenta/seguridad")).StatusCode);
        await api.EntrarAsync(email, "Clave-recuperada-2026");
        await api.CorreoParaAsync(email, "Tu contraseña fue cambiada"); // aviso de seguridad
    }

    [ApiFact]
    public async Task AdminNoPuedeQuitarseSuRol_NiDesactivarse_NiBorrarse()
    {
        var (id, email) = await api.CrearUsuarioAsync(Roles.Admin);
        using var admin = api.Cliente(await api.EntrarAsync(email, TestDb.PasswordDePrueba));
        var u = await admin.GetAsync($"api/admin/usuarios/{id}").Ok();

        await admin.PostJson($"api/admin/usuarios/{id}/desactivar").Esperar(HttpStatusCode.BadRequest);
        await admin.DeleteAsync($"api/admin/usuarios/{id}").Esperar(HttpStatusCode.BadRequest);
        await admin.PutJson($"api/admin/usuarios/{id}", new
        {
            nombre = u.Str("nombre"), apellido = u.Str("apellido"), telefono = "55550199", email, codigoCorporativo = u.Str("codigoCorporativo"), rol = Roles.Vendedor
        }).Esperar(HttpStatusCode.BadRequest);
    }

    [ApiFact]
    public async Task Probabilidades_SoloLasCambiaElAdmin_YCambianElPronostico()
    {
        using var admin = await api.ComoAsync(Roles.Admin);
        object Etapas(params int[] v) => new { etapas = EstadosVenta.Orden.Select((e, i) => new { estado = e, probabilidad = v[i] }) };

        await admin.PutJson("api/reportes/pronostico/probabilidades", Etapas(10, 5, 50, 75, 90, 100)).Rechazo("menos probabilidad");
        await admin.PutJson("api/reportes/pronostico/probabilidades", Etapas(10, 25, 50, 75, 90, 80)).Rechazo("100 %");
        await admin.PutJson("api/reportes/pronostico/probabilidades", Etapas(20, 30, 50, 75, 90, 100)).Ok();

        var r = await admin.GetAsync("api/reportes/pronostico").Ok();
        Assert.Equal(20m, r.GetProperty("etapas")[0].Dec("probabilidad"));
        Assert.Equal(r.Dec("pronostico"), r.GetProperty("etapas").EnumerateArray().Sum(e => e.Dec("ponderado")));

        await admin.PutJson("api/reportes/pronostico/probabilidades", Etapas(10, 25, 50, 75, 90, 100)).Ok(); // deja los iniciales
    }

    [ApiFact]
    public async Task FotoDeProducto_SeSube_SeSirvePublica_ConTipoCorrecto_YSeBorra()
    {
        var producto = await ProductoConStock(1);
        using var bodega = await api.ComoAsync(Roles.Bodega);
        var png = Convert.FromBase64String("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==");
        var contenido = new ByteArrayContent(png);
        contenido.Headers.ContentType = new("image/png");
        var subida = await bodega.PostAsync($"api/inventario/productos/{producto}/imagenes",
            new MultipartFormDataContent { { contenido, "archivo", "punto.png" } }).Ok();
        var imagen = subida[0].GetInt32(); // ids de las fotos del producto, la principal primero

        using var publico = api.Cliente();
        using var r = await publico.GetAsync($"api/productos/{producto}/imagenes/{imagen}");
        Assert.Equal(HttpStatusCode.OK, r.StatusCode);
        Assert.Equal("image/png", r.Content.Headers.ContentType?.MediaType);
        Assert.Equal(png, await r.Content.ReadAsByteArrayAsync());
        Assert.Equal(HttpStatusCode.NotFound, (await publico.GetAsync($"api/productos/{producto + 1}/imagenes/{imagen}")).StatusCode);

        await bodega.DeleteAsync($"api/inventario/productos/{producto}/imagenes/{imagen}").Ok();
        Assert.Equal(HttpStatusCode.NotFound, (await publico.GetAsync($"api/productos/{producto}/imagenes/{imagen}")).StatusCode);
    }

    [ApiFact]
    public async Task Panel_YReportes_ResponderConLosDatosDelDia_ParaCadaRol()
    {
        foreach (var rol in new[] { Roles.Admin, Roles.Bodega, Roles.Compras, Roles.Contador })
        {
            using var http = await api.ComoAsync(rol);
            await http.GetAsync("api/panel").Ok();
        }
        using var contador = await api.ComoAsync(Roles.Contador);
        foreach (var url in new[] { "api/reportes/ventas", "api/reportes/pronostico", "api/contabilidad/reportes/estado-resultados",
                                    "api/contabilidad/reportes/balance-general", "api/contabilidad/reportes/balance-comprobacion" })
            await contador.GetAsync(url).Ok();
    }
}
