using System.Net;
using System.Reflection;
using System.Text;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.Routing;
using Pedidos.Api.Domain;

namespace Pedidos.Tests.Http;

/// <summary>
/// Matriz de permisos: cada endpoint de la API, con cada rol y sin sesión. Los permisos esperados se escriben
/// aquí a mano según lo que debe poder hacer cada área (no se leen de los atributos del código), así un
/// [Authorize] mal puesto hace fallar la prueba. Las peticiones usan ids inexistentes o cuerpos vacíos para no
/// cambiar datos: lo que importa es si la API deja pasar (cualquier código salvo 401/403) o no (403).
/// </summary>
[Collection(ApiColeccion.Nombre)]
public class AutorizacionHttpTests(ApiEnVivo api)
{
    private const string V = Roles.Vendedor, A = Roles.Admin, B = Roles.Bodega, C = Roles.Compras, K = Roles.Contador;
    private static readonly string[] Todos = { V, A, B, C, K };
    private static readonly string[] Anonimo = Array.Empty<string>();

    /// <param name="Plantilla">Ruta tal como está en el controlador (para comprobar que no falta ningún endpoint).</param>
    /// <param name="Roles">Quién puede; <see cref="Anonimo"/> = no requiere sesión.</param>
    public sealed record Endpoint(string Metodo, string Url, string Plantilla, string[] Roles, string? Cuerpo = "{}")
    {
        public bool EsAnonimo => Roles.Length == 0;
        public override string ToString() => $"{Metodo} {Url}";
    }

    private const int X = 999_999; // id que no existe

    /// <summary>La subida de fotos solo acepta multipart/form-data (con otro formato responde 415 antes de mirar el rol).</summary>
    private const string Multipart = "<multipart>";

    public static readonly Endpoint[] Endpoints =
    {
        // Autenticación (sin sesión)
        new("POST", "api/auth/login", "api/auth/login", Anonimo),
        new("POST", "api/auth/login/verificar", "api/auth/login/verificar", Anonimo),
        new("POST", "api/auth/recuperar", "api/auth/recuperar", Anonimo),
        new("POST", "api/auth/restablecer", "api/auth/restablecer", Anonimo),
        new("GET", $"api/productos/{X}/imagenes/1", "api/productos/{id:int}/imagenes/{imagenId:int}", Anonimo, null),

        // Mi cuenta: cualquier usuario con sesión
        new("GET", "api/cuenta/seguridad", "api/cuenta/seguridad", Todos, null),
        new("POST", "api/cuenta/password", "api/cuenta/password", Todos),
        new("POST", "api/cuenta/2fa/totp", "api/cuenta/2fa/totp", Todos),
        new("POST", "api/cuenta/2fa/totp/confirmar", "api/cuenta/2fa/totp/confirmar", Todos),
        new("POST", "api/cuenta/2fa/desactivar", "api/cuenta/2fa/desactivar", Todos),
        new("POST", "api/cuenta/2fa/codigos-respaldo", "api/cuenta/2fa/codigos-respaldo", Todos),
        new("GET", "api/cuenta/accesos", "api/cuenta/accesos", Todos, null),
        new("GET", "api/geografia", "api/geografia", Todos, null),
        new("GET", "api/productos", "api/productos", Todos, null),
        new("GET", $"api/productos/{X}", "api/productos/{id:int}", Todos, null),

        // Administración
        new("GET", "api/admin/bitacora", "api/admin/bitacora", new[] { A }, null),
        new("GET", "api/admin/usuarios", "api/admin/usuarios", new[] { A }, null),
        new("GET", $"api/admin/usuarios/{X}", "api/admin/usuarios/{id:int}", new[] { A }, null),
        new("POST", "api/admin/usuarios", "api/admin/usuarios", new[] { A }),
        new("PUT", $"api/admin/usuarios/{X}", "api/admin/usuarios/{id:int}", new[] { A }),
        new("POST", $"api/admin/usuarios/{X}/activar", "api/admin/usuarios/{id:int}/activar", new[] { A }),
        new("POST", $"api/admin/usuarios/{X}/desactivar", "api/admin/usuarios/{id:int}/desactivar", new[] { A }),
        new("POST", $"api/admin/usuarios/{X}/invitacion", "api/admin/usuarios/{id:int}/invitacion", new[] { A }),
        new("DELETE", $"api/admin/usuarios/{X}", "api/admin/usuarios/{id:int}", new[] { A }, null),

        // Ventas: el vendedor factura; administración y contabilidad consultan
        new("POST", "api/pedidos", "api/pedidos", new[] { V }),
        new("GET", "api/pedidos", "api/pedidos", new[] { V, A, K }, null),
        new("GET", $"api/pedidos/{X}", "api/pedidos/{id:int}", new[] { V, A, K }, null),
        new("GET", "api/clientes", "api/clientes", new[] { V, A }, null),
        new("POST", "api/clientes", "api/clientes", new[] { V, A }),
        new("PUT", $"api/clientes/{X}", "api/clientes/{id:int}", new[] { V, A }),
        new("GET", "api/reportes/ventas", "api/reportes/ventas", new[] { V, A, K }, null),
        new("GET", "api/reportes/pronostico", "api/reportes/pronostico", new[] { V, A, K }, null),
        new("PUT", "api/reportes/pronostico/probabilidades", "api/reportes/pronostico/probabilidades", new[] { A }),

        // Pipeline: vendedor, administración, contabilidad y bodega (compras no)
        new("GET", "api/pipeline", "api/pipeline", new[] { V, A, K, B }, null),
        new("GET", $"api/pipeline/{X}", "api/pipeline/{id:int}", new[] { V, A, K, B }, null),
        new("POST", $"api/pipeline/{X}/avanzar", "api/pipeline/{id:int}/avanzar", new[] { V, A, K, B }),

        // Inventario: todos consultan salvo el vendedor; solo bodega y administración modifican
        new("GET", "api/inventario/productos", "api/inventario/productos", new[] { A, B, C, K }, null),
        new("POST", "api/inventario/productos", "api/inventario/productos", new[] { A, B }),
        new("PUT", $"api/inventario/productos/{X}", "api/inventario/productos/{id:int}", new[] { A, B }),
        new("DELETE", $"api/inventario/productos/{X}", "api/inventario/productos/{id:int}", new[] { A, B }, null),
        new("POST", $"api/inventario/productos/{X}/imagenes", "api/inventario/productos/{id:int}/imagenes", new[] { A, B }, Multipart),
        new("DELETE", $"api/inventario/productos/{X}/imagenes/1", "api/inventario/productos/{id:int}/imagenes/{imagenId:int}", new[] { A, B }, null),
        new("POST", $"api/inventario/productos/{X}/imagenes/1/principal", "api/inventario/productos/{id:int}/imagenes/{imagenId:int}/principal", new[] { A, B }),
        new("GET", $"api/inventario/productos/{X}/kardex", "api/inventario/productos/{id:int}/kardex", new[] { A, B, C, K }, null),
        new("POST", "api/inventario/ajustes", "api/inventario/ajustes", new[] { A, B }),

        // Compras: compras gestiona; bodega recibe; contabilidad consulta
        new("GET", "api/compras/proveedores", "api/compras/proveedores", new[] { A, B, C, K }, null),
        new("POST", "api/compras/proveedores", "api/compras/proveedores", new[] { A, C }),
        new("PUT", $"api/compras/proveedores/{X}", "api/compras/proveedores/{id:int}", new[] { A, C }),
        new("GET", "api/compras/ordenes", "api/compras/ordenes", new[] { A, B, C, K }, null),
        new("GET", $"api/compras/ordenes/{X}", "api/compras/ordenes/{id:int}", new[] { A, B, C, K }, null),
        new("POST", "api/compras/ordenes", "api/compras/ordenes", new[] { A, C }),
        new("POST", $"api/compras/ordenes/{X}/recibir", "api/compras/ordenes/{id:int}/recibir", new[] { A, B, C }),
        new("POST", $"api/compras/ordenes/{X}/anular", "api/compras/ordenes/{id:int}/anular", new[] { A, C }),

        // Contabilidad
        new("GET", "api/contabilidad/cuentas", "api/contabilidad/cuentas", new[] { A, K }, null),
        new("POST", "api/contabilidad/cuentas", "api/contabilidad/cuentas", new[] { A, K }),
        new("PUT", $"api/contabilidad/cuentas/{X}", "api/contabilidad/cuentas/{id:int}", new[] { A, K }),
        new("GET", "api/contabilidad/partidas", "api/contabilidad/partidas", new[] { A, K }, null),
        new("GET", $"api/contabilidad/partidas/{X}", "api/contabilidad/partidas/{id:int}", new[] { A, K }, null),
        new("POST", "api/contabilidad/partidas", "api/contabilidad/partidas", new[] { A, K }),
        new("GET", $"api/contabilidad/reportes/mayor/{X}", "api/contabilidad/reportes/mayor/{cuentaId:int}", new[] { A, K }, null),
        new("GET", "api/contabilidad/reportes/balance-comprobacion", "api/contabilidad/reportes/balance-comprobacion", new[] { A, K }, null),
        new("GET", "api/contabilidad/reportes/estado-resultados", "api/contabilidad/reportes/estado-resultados", new[] { A, K }, null),
        new("GET", "api/contabilidad/reportes/balance-general", "api/contabilidad/reportes/balance-general", new[] { A, K }, null),

        // Panel: todas las áreas menos el vendedor (él entra al catálogo)
        new("GET", "api/panel", "api/panel", new[] { A, B, C, K }, null),
    };

    public static IEnumerable<object[]> Casos => Endpoints.Select(e => new object[] { e });

    private static HttpRequestMessage Peticion(Endpoint e) => new(new HttpMethod(e.Metodo), e.Url)
    {
        Content = e.Cuerpo switch
        {
            null => null,
            Multipart => new MultipartFormDataContent { { new ByteArrayContent(new byte[] { 1, 2, 3 }), "archivo", "foto.jpg" } },
            _ => new StringContent(e.Cuerpo, Encoding.UTF8, "application/json")
        }
    };

    [ApiFact]
    public void LaMatriz_CubreTodosLosEndpointsDeLaApi()
    {
        var enCodigo = typeof(Roles).Assembly.GetTypes()
            .Where(t => typeof(ControllerBase).IsAssignableFrom(t) && !t.IsAbstract)
            .SelectMany(t =>
            {
                var baseRuta = t.GetCustomAttribute<RouteAttribute>()?.Template ?? "";
                return t.GetMethods(BindingFlags.Public | BindingFlags.Instance | BindingFlags.DeclaredOnly)
                    .SelectMany(m => m.GetCustomAttributes<HttpMethodAttribute>())
                    .SelectMany(h => h.HttpMethods.Select(verbo =>
                        $"{verbo} {(string.IsNullOrEmpty(h.Template) ? baseRuta : $"{baseRuta}/{h.Template}")}"));
            })
            .ToHashSet();
        var enMatriz = Endpoints.Select(e => $"{e.Metodo} {e.Plantilla}").ToHashSet();

        Assert.Empty(enCodigo.Except(enMatriz)); // endpoint nuevo sin permisos revisados: agrégalo a la matriz
        Assert.Empty(enMatriz.Except(enCodigo)); // la matriz menciona algo que ya no existe
    }

    [ApiTheory]
    [MemberData(nameof(Casos))]
    public async Task SinSesion_SoloPasanLosEndpointsPublicos(Endpoint e)
    {
        using var http = api.Cliente();
        using var r = await http.SendAsync(Peticion(e));
        var cuerpo = await r.Content.ReadAsStringAsync();
        if (e.EsAnonimo)
        {
            Assert.NotEqual(HttpStatusCode.Unauthorized, r.StatusCode);
            Assert.NotEqual(HttpStatusCode.Forbidden, r.StatusCode);
        }
        else
        {
            Assert.True(r.StatusCode == HttpStatusCode.Unauthorized, $"{e}: {(int)r.StatusCode} {cuerpo}");
            Assert.Contains("\"error\"", cuerpo); // mensaje para el usuario, no una página vacía
        }
    }

    [ApiTheory]
    [InlineData(Roles.Vendedor)]
    [InlineData(Roles.Admin)]
    [InlineData(Roles.Bodega)]
    [InlineData(Roles.Compras)]
    [InlineData(Roles.Contador)]
    public async Task CadaRol_SoloEntraASusModulos(string rol)
    {
        using var http = await api.ComoAsync(rol); // un cliente (una IP) por rol: no choca con el límite global
        var errores = new List<string>();
        foreach (var e in Endpoints.Where(x => !x.EsAnonimo))
        {
            using var r = await http.SendAsync(Peticion(e));
            var permitido = e.Roles.Contains(rol);
            var codigo = (int)r.StatusCode;
            if (codigo >= 500)
                errores.Add($"{e}: {codigo} (error del servidor) {await r.Content.ReadAsStringAsync()}");
            else if (permitido && r.StatusCode is HttpStatusCode.Forbidden or HttpStatusCode.Unauthorized)
                errores.Add($"{e}: debería permitirlo y respondió {codigo}");
            else if (!permitido && r.StatusCode != HttpStatusCode.Forbidden)
                errores.Add($"{e}: debería negarlo (403) y respondió {codigo}");
        }
        Assert.True(errores.Count == 0, $"Rol {rol}:\n" + string.Join("\n", errores));
    }
}
