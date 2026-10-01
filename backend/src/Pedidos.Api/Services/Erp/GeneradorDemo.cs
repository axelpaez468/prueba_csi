using Microsoft.EntityFrameworkCore;
using Pedidos.Api.Data;
using Pedidos.Api.Domain;
using Pedidos.Api.Dtos;
using Pedidos.Api.Errors;
using Pedidos.Api.Services.Usuarios;

namespace Pedidos.Api.Services.Erp;

/// <summary>Reloj que el generador mueve a mano para registrar operaciones "en el pasado".</summary>
public sealed class RelojDemo : TimeProvider
{
    public DateTimeOffset Ahora { get; set; }

    public override DateTimeOffset GetUtcNow() => Ahora;
}

/// <summary>
/// Datos de demostración: productos, clientes y vendedores repartidos por Guatemala y varios meses de operación
/// (compras recibidas, ventas con entrega, avance del pipeline, gastos y depósitos). Todo pasa por los mismos
/// servicios de la aplicación, así que inventario, kardex y contabilidad quedan cuadrados igual que en el uso real.
/// Solo se ejecuta una vez (si no existe el producto P-006) y solo si está habilitado (Demo:Generar).
/// </summary>
public class GeneradorDemo
{
    public const string Marcador = "P-006";

    private readonly Func<AppDbContext> _contexto;
    private readonly ILogger? _log;
    private readonly Random _azar = new(2026);
    private readonly RelojDemo _reloj = new();

    public GeneradorDemo(Func<AppDbContext> contexto, ILogger? log = null)
    {
        _contexto = contexto;
        _log = log;
    }

    private sealed record ProductoDemo(string Codigo, string Nombre, string Marca, string Categoria, decimal Precio, decimal Costo,
        int Garantia, int Popularidad, string Descripcion, (string, string)[] Specs);

    private static readonly ProductoDemo[] Catalogo =
    {
        new("P-006", "Laptop ultradelgada 14\"", "Nimbus", "Computadoras", 6499m, 4600m, 12, 3,
            "Laptop ligera de 1.3 kg con pantalla Full HD de 14 pulgadas y batería para toda la jornada. Ideal para trabajo de oficina, clases y videollamadas.\n\nIncluye procesador de 8 núcleos, 16 GB de memoria y almacenamiento SSD de 512 GB, con lector de huella para iniciar sesión.",
            new[] { ("Procesador", "8 núcleos, hasta 4.4 GHz"), ("Memoria", "16 GB DDR5"), ("Almacenamiento", "SSD NVMe de 512 GB"), ("Pantalla", "14\" Full HD IPS antirreflejo"), ("Batería", "Hasta 12 horas"), ("Peso", "1.3 kg") }),
        new("P-007", "Laptop gamer 15.6\" RTX", "Nimbus", "Computadoras", 11999m, 8700m, 12, 1,
            "Laptop para juegos y diseño 3D con tarjeta gráfica dedicada y pantalla de 144 Hz. Su sistema de enfriamiento con doble ventilador mantiene el rendimiento en sesiones largas.\n\nTeclado retroiluminado RGB por zonas y puertos para conectar dos monitores externos.",
            new[] { ("Gráficos", "RTX con 8 GB GDDR6"), ("Procesador", "12 núcleos, hasta 4.9 GHz"), ("Memoria", "16 GB DDR5 (ampliable a 32 GB)"), ("Pantalla", "15.6\" 144 Hz IPS"), ("Almacenamiento", "SSD de 1 TB") }),
        new("P-008", "Monitor curvo 32\"", "Vista", "Monitores", 3299m, 2150m, 36, 2,
            "Monitor curvo de 32 pulgadas con resolución QHD que envuelve el campo de visión: ideal para hojas de cálculo grandes, edición y juegos.\n\nPanel VA de alto contraste, 165 Hz y base con ajuste de inclinación.",
            new[] { ("Tamaño", "32\" curvo 1500R"), ("Resolución", "2560 x 1440 (QHD)"), ("Frecuencia", "165 Hz"), ("Entradas", "2 HDMI y 1 DisplayPort") }),
        new("P-009", "Monitor 24\" Full HD", "Vista", "Monitores", 1399m, 900m, 24, 5,
            "Monitor de 24 pulgadas Full HD con bordes delgados, ideal para armar estaciones de trabajo de dos pantallas.\n\nModo de lectura con luz azul reducida y montaje VESA.",
            new[] { ("Tamaño", "24\""), ("Resolución", "1920 x 1080"), ("Panel", "IPS, 75 Hz"), ("Entradas", "HDMI y VGA") }),
        new("P-010", "Teclado inalámbrico compacto", "KeyForge", "Periféricos", 299m, 165m, 12, 8,
            "Teclado compacto inalámbrico y silencioso, perfecto para escritorios pequeños y para llevar con la laptop.\n\nSe conecta a tres equipos y cambia entre ellos con una tecla.",
            new[] { ("Conexión", "Bluetooth y receptor USB"), ("Distribución", "Español latinoamericano"), ("Batería", "2 pilas AAA, hasta 24 meses"), ("Peso", "390 g") }),
        new("P-011", "Mouse gamer RGB", "Orion", "Periféricos", 349m, 190m, 12, 7,
            "Mouse para juegos con sensor de 16,000 DPI, 7 botones programables e iluminación RGB personalizable.\n\nCable trenzado y patas de PTFE para un deslizamiento suave.",
            new[] { ("Sensor", "Óptico, hasta 16,000 DPI"), ("Botones", "7 programables"), ("Peso", "85 g"), ("Conexión", "USB, cable trenzado de 1.8 m") }),
        new("P-012", "Combo teclado y mouse", "Orion", "Periféricos", 259m, 140m, 12, 9,
            "Combo inalámbrico de teclado y mouse con un solo receptor USB: la opción práctica para oficinas y hogares.\n\nTeclado resistente a salpicaduras y mouse ambidiestro.",
            new[] { ("Conexión", "Receptor USB 2.4 GHz único"), ("Teclado", "Tamaño completo, resistente a salpicaduras"), ("Mouse", "1,600 DPI, ambidiestro") }),
        new("P-013", "Audífonos inalámbricos con cancelación de ruido", "SonicWave", "Audio", 1199m, 720m, 12, 4,
            "Audífonos de diadema con cancelación activa de ruido para concentrarse en la oficina o viajar sin distracciones.\n\nHasta 30 horas de batería y carga rápida: 10 minutos dan 3 horas de uso.",
            new[] { ("Cancelación de ruido", "Activa, con modo ambiente"), ("Batería", "Hasta 30 horas"), ("Conexión", "Bluetooth 5.3 y cable de 3.5 mm"), ("Micrófonos", "4, para llamadas claras") }),
        new("P-014", "Bocina Bluetooth portátil", "SonicWave", "Audio", 459m, 260m, 12, 6,
            "Bocina portátil resistente al agua (IPX7) con sonido de 360 grados y 12 horas de batería.\n\nSe puede emparejar con otra bocina igual para sonido estéreo.",
            new[] { ("Potencia", "20 W"), ("Resistencia", "IPX7"), ("Batería", "12 horas"), ("Conexión", "Bluetooth 5.1") }),
        new("P-015", "Micrófono USB de condensador", "SonicWave", "Audio", 699m, 410m, 12, 3,
            "Micrófono de condensador para pódcast, clases en línea y transmisiones, con calidad de estudio y conexión USB sin controladores.\n\nIncluye trípode, filtro antipop y salida para audífonos.",
            new[] { ("Patrón", "Cardioide"), ("Resolución", "24 bits / 96 kHz"), ("Conexión", "USB-C"), ("Incluye", "Trípode y filtro antipop") }),
        new("P-016", "Disco SSD externo 1 TB", "DataVault", "Almacenamiento", 899m, 560m, 36, 5,
            "Disco de estado sólido externo de 1 TB, del tamaño de una tarjeta de crédito y hasta 10 veces más rápido que un disco duro.\n\nCarcasa de aluminio resistente a golpes.",
            new[] { ("Capacidad", "1 TB"), ("Velocidad", "Hasta 1,050 MB/s"), ("Conexión", "USB-C 3.2 (incluye adaptador USB-A)") }),
        new("P-017", "Memoria USB 128 GB", "DataVault", "Almacenamiento", 119m, 62m, 12, 10,
            "Memoria USB 3.0 de 128 GB con carcasa metálica y argolla para llavero.\n\nTransfiere una película completa en menos de un minuto.",
            new[] { ("Capacidad", "128 GB"), ("Interfaz", "USB 3.0"), ("Lectura", "Hasta 150 MB/s") }),
        new("P-018", "Router Wi-Fi 6 doble banda", "NetLink", "Redes", 789m, 480m, 24, 4,
            "Router Wi-Fi 6 que cubre hasta 150 m² y conecta más de 40 dispositivos sin perder velocidad.\n\nSe configura desde el teléfono en minutos e incluye control parental.",
            new[] { ("Estándar", "Wi-Fi 6 (802.11ax)"), ("Velocidad", "Hasta 1.8 Gbps"), ("Puertos", "4 LAN gigabit + 1 WAN"), ("Antenas", "4 externas") }),
        new("P-019", "Switch 8 puertos gigabit", "NetLink", "Redes", 329m, 190m, 24, 3,
            "Switch de 8 puertos gigabit sin configuración: se conecta y funciona.\n\nCarcasa metálica para montar en pared.",
            new[] { ("Puertos", "8 x 10/100/1000"), ("Carcasa", "Metálica"), ("Consumo", "4 W") }),
        new("P-020", "Impresora multifuncional de tinta continua", "PrintMax", "Impresión", 1899m, 1250m, 12, 3,
            "Imprime, copia y escanea con tinta continua: hasta 7,500 páginas a color con las botellas incluidas.\n\nWi-Fi para imprimir desde el teléfono.",
            new[] { ("Funciones", "Imprime, copia y escanea"), ("Rendimiento", "7,500 páginas a color"), ("Conexión", "Wi-Fi y USB"), ("Velocidad", "10 ppm") }),
        new("P-021", "Webcam 4K con micrófono", "ClearCam", "Video", 899m, 520m, 12, 4,
            "Cámara web 4K con enfoque automático, corrección de luz y micrófonos con reducción de ruido para reuniones profesionales.\n\nTapa de privacidad y montaje para monitor o trípode.",
            new[] { ("Resolución", "4K a 30 fps / 1080p a 60 fps"), ("Campo de visión", "90°"), ("Micrófonos", "Doble, con reducción de ruido") }),
        new("P-022", "UPS 1000 VA", "VoltGuard", "Energía", 999m, 640m, 24, 3,
            "Respaldo de energía de 1000 VA con regulador de voltaje: protege computadoras y routers de apagones y picos.\n\n6 tomacorrientes y alarma de batería baja.",
            new[] { ("Capacidad", "1000 VA / 600 W"), ("Tomacorrientes", "6 (4 con respaldo)"), ("Respaldo", "Hasta 20 minutos con una PC") }),
        new("P-023", "Tablet 10\" 128 GB", "Nimbus", "Tablets", 2499m, 1700m, 12, 2,
            "Tablet de 10 pulgadas para estudiar, leer y ver contenido, con 128 GB de almacenamiento y batería de todo el día.\n\nCompatible con lápiz digital.",
            new[] { ("Pantalla", "10.4\" 2K"), ("Almacenamiento", "128 GB + microSD"), ("Batería", "7,040 mAh") }),
        new("P-024", "Silla ergonómica de oficina", "ErgoPlus", "Mobiliario", 1599m, 950m, 12, 2,
            "Silla ergonómica con respaldo de malla transpirable, soporte lumbar ajustable y apoyabrazos 3D.\n\nSoporta hasta 120 kg y se reclina hasta 130 grados.",
            new[] { ("Respaldo", "Malla, soporte lumbar ajustable"), ("Apoyabrazos", "3D"), ("Capacidad", "120 kg") }),
        new("P-025", "Hub USB-C 7 en 1", "Orion", "Accesorios", 279m, 140m, 12, 6,
            "Adaptador USB-C 7 en 1 para laptops: HDMI 4K, tres puertos USB, lector de tarjetas y carga de 100 W.\n\nCuerpo de aluminio que disipa el calor.",
            new[] { ("Puertos", "HDMI 4K, 3 USB-A, SD, microSD, USB-C PD"), ("Carga", "Hasta 100 W") }),
    };

    /// <summary>Peso de cada departamento en las ventas (la capital concentra más).</summary>
    private static readonly (string Departamento, int Peso)[] PesoDepartamentos =
    {
        ("Guatemala", 34), ("Quetzaltenango", 9), ("Escuintla", 7), ("Sacatepéquez", 6), ("Chimaltenango", 4),
        ("Huehuetenango", 4), ("Alta Verapaz", 4), ("San Marcos", 4), ("Petén", 3), ("Izabal", 3), ("Chiquimula", 3),
        ("Jutiapa", 3), ("Suchitepéquez", 3), ("Santa Rosa", 2), ("Retalhuleu", 2), ("Zacapa", 2), ("Sololá", 2),
        ("Quiché", 2), ("Totonicapán", 1), ("Baja Verapaz", 1), ("El Progreso", 1), ("Jalapa", 1),
    };

    private static readonly string[] Empresas =
    {
        "Comercial El Progreso", "Distribuidora La Económica", "Librería y Papelería San José", "Colegio Mixto Las Américas",
        "Clínica Médica Familiar", "Ferretería Los Altos", "Café Volcán, S.A.", "Hotel Posada del Lago",
        "Agencia de Viajes Maya Tours", "Constructora del Valle", "Farmacia La Salud", "Bufete Jurídico Hernández & Asociados",
        "Restaurante El Fogón", "Cooperativa Integral El Ahorro", "Academia de Computación TecnoFuturo", "Óptica Visión Clara",
        "Transportes del Norte", "Panadería La Espiga", "Estudio Fotográfico Luz y Color", "Consultora Contable Pérez",
        "Supermercado La Familia", "Gimnasio Fuerza Total", "Taller Mecánico El Pistón", "Escuela de Idiomas Global",
    };

    private static readonly string[] Calles = { "avenida", "calle" };

    private int Entre(int min, int max) => _azar.Next(min, max + 1);

    private T Elegir<T>(IReadOnlyList<T> lista) => lista[_azar.Next(lista.Count)];

    private string DepartamentoAlAzar()
    {
        var total = PesoDepartamentos.Sum(d => d.Peso);
        var n = _azar.Next(total);
        foreach (var (d, p) in PesoDepartamentos)
        {
            if (n < p) return d;
            n -= p;
        }
        return "Guatemala";
    }

    private (string Departamento, string Municipio, string Direccion) LugarAlAzar()
    {
        var depto = DepartamentoAlAzar();
        var municipios = Geografia.Departamentos.First(d => d.Nombre == depto).Municipios;
        // La cabecera (primer municipio) recibe más pedidos que el resto.
        var muni = _azar.NextDouble() < 0.5 ? municipios[0] : Elegir(municipios);
        var direccion = $"{Entre(1, 20)}a. {Elegir(Calles)} {Entre(1, 30)}-{Entre(10, 99)}, zona {Entre(1, 18)}";
        return (depto, muni, direccion);
    }

    private string NitAlAzar()
    {
        var cuerpo = Entre(1_000_000, 9_999_999).ToString();
        var suma = cuerpo.Select((c, i) => (c - '0') * (cuerpo.Length + 1 - i)).Sum();
        var d = (11 - suma % 11) % 11;
        return cuerpo + (d == 10 ? "K" : d.ToString());
    }

    /// <summary>Hora local (Guatemala) del día indicado, en UTC.</summary>
    private static DateTimeOffset Momento(DateOnly dia, int hora, int minuto) =>
        new DateTimeOffset(Calendario.InicioUtc(dia)).AddHours(hora).AddMinutes(minuto);

    public async Task<bool> GenerarAsync(int dias, CancellationToken ct)
    {
        await using (var db = _contexto())
            if (await db.Productos.AnyAsync(p => p.Codigo == Marcador, ct))
                return false;

        var hoy = Calendario.Hoy(TimeProvider.System);
        var inicio = hoy.AddDays(-dias);
        _reloj.Ahora = Momento(inicio, 7, 0);
        _log?.LogInformation("Generando datos de demostración desde {Inicio} ({Dias} días)...", inicio, dias);

        int admin, bodega, compras, contador;
        List<int> vendedores;
        Dictionary<string, int> cuentas;
        await using (var db = _contexto())
        {
            int Rol(string r) => db.Usuarios.Where(u => u.Rol == r && u.Activo).OrderBy(u => u.Id).Select(u => u.Id).FirstOrDefault();
            admin = Rol(Roles.Admin);
            bodega = Rol(Roles.Bodega) is var b && b != 0 ? b : admin;
            compras = Rol(Roles.Compras) is var c && c != 0 ? c : admin;
            contador = Rol(Roles.Contador) is var k && k != 0 ? k : admin;
            vendedores = await CrearVendedoresAsync(db, ct);
            cuentas = await db.CuentasContables.ToDictionaryAsync(x => x.Codigo, x => x.Id, ct);
        }

        // ---------- Catálogo, proveedores y clientes ----------
        var clientes = new List<(int Id, string Depto, string Muni, string Dir)>();
        var proveedores = new List<int>();
        await using (var db = _contexto())
        {
            var conta = new ContabilidadService(db, _reloj);
            var inventario = new InventarioService(db, conta, _reloj);
            foreach (var p in Catalogo)
                await inventario.CrearAsync(new GuardarProductoRequest(p.Codigo, p.Nombre, p.Precio, Math.Max(2, p.Popularidad), true,
                    p.Marca, p.Categoria, p.Descripcion, p.Garantia, p.Specs.Select(s => new EspecificacionDto(s.Item1, s.Item2)).ToList()), ct);

            var terceros = new TercerosService(db, _reloj);
            foreach (var (nombre, contacto) in new[] { ("Mayoreo Digital, S.A.", "Rosa Aguilar"), ("Tecno Importaciones Centroamérica", "Mario Solís") })
            {
                try
                {
                    await terceros.CrearProveedorAsync(new GuardarProveedorRequest(NitAlAzar(), nombre, contacto, $"2{Entre(2000000, 9999999)}",
                        null, "Ciudad de Guatemala", true), ct);
                }
                catch (BusinessRuleException) { /* NIT repetido por azar: se omite */ }
            }
            proveedores = await db.Proveedores.Where(p => p.Activo).Select(p => p.Id).ToListAsync(ct);

            foreach (var empresa in Empresas)
            {
                var (depto, muni, dir) = LugarAlAzar();
                try
                {
                    var c = await terceros.CrearClienteAsync(new GuardarClienteRequest(NitAlAzar(), empresa, $"{dir}, {muni}, {depto}",
                        $"{Entre(2, 7)}{Entre(1000000, 9999999)}", null, true), ct);
                    clientes.Add((c.Id, depto, muni, dir));
                }
                catch (BusinessRuleException) { /* NIT repetido por azar: se omite */ }
            }

            // Aporte de capital para financiar el inventario inicial.
            await conta.CrearManualAsync(new CrearPartidaRequest(inicio, "Aporte de capital de los socios para inventario",
                new() { new(cuentas[CuentasSistema.Bancos], 400_000m, 0), new(cuentas[CuentasSistema.Capital], 0, 400_000m) }), contador, ct);
        }

        var catalogo = await CargarCatalogoAsync(ct);
        var popularidad = Catalogo.ToDictionary(p => p.Codigo, p => p.Popularidad);

        // ---------- Operación día por día ----------
        var efectivoSemana = 0m;
        var ventasHechas = 0;
        for (var d = 0; d <= dias; d++)
        {
            ct.ThrowIfCancellationRequested();
            var dia = inicio.AddDays(d);
            await using var db = _contexto();
            var conta = new ContabilidadService(db, _reloj);

            // Lunes (y el primer día): reposición de inventario para dos semanas.
            if (d == 0 || dia.DayOfWeek == DayOfWeek.Monday)
                await ReponerAsync(db, conta, dia, catalogo, popularidad, proveedores, compras, bodega, d == 0, ct);

            // Ventas del día: más entre semana y con una tendencia creciente.
            var factor = dia.DayOfWeek switch { DayOfWeek.Sunday => 0.3, DayOfWeek.Saturday => 0.6, _ => 1.0 };
            var cantidad = (int)Math.Round((4 + 4.0 * d / Math.Max(1, dias) + _azar.NextDouble() * 3) * factor);
            var ventasDelDia = new List<(int Id, int Vendedor, int Hora)>();
            for (var i = 0; i < cantidad; i++)
            {
                var hora = Entre(8, 18);
                _reloj.Ahora = Momento(dia, hora, Entre(0, 59));
                var vendedor = Elegir(vendedores);
                var lineas = LineasAlAzar(catalogo, popularidad);
                // 72 % a clientes registrados (se entrega en su dirección); el resto a consumidor final.
                int? clienteId = null;
                string depto, muni, dir;
                if (clientes.Count > 0 && _azar.NextDouble() < 0.72)
                {
                    var c = Elegir(clientes);
                    (clienteId, depto, muni, dir) = (c.Id, c.Depto, c.Muni, c.Dir);
                }
                else
                {
                    (depto, muni, dir) = LugarAlAzar();
                }
                var forma = _azar.NextDouble() switch { < 0.5 => FormasPago.Efectivo, < 0.8 => FormasPago.Tarjeta, _ => FormasPago.Transferencia };
                try
                {
                    var venta = await new PedidoService(db, _reloj, conta).CrearAsync(vendedor,
                        new CrearPedidoRequest(lineas, clienteId, forma, dir, depto, muni), ct);
                    if (forma == FormasPago.Efectivo) efectivoSemana += venta.Total;
                    ventasDelDia.Add((venta.Numero, vendedor, hora));
                    ventasHechas++;
                }
                catch (BusinessRuleException)
                {
                    // Sin existencia suficiente: esa venta no se concreta (como en la vida real).
                }
            }

            // Avance del pipeline según la antigüedad de cada venta.
            foreach (var (id, vendedor, hora) in ventasDelDia)
                await AvanzarPipelineAsync(db, id, vendedor, dia, hora, hoy, admin, contador, bodega, ct);

            // Viernes: depósito del efectivo de la semana. Día 1: gastos fijos del mes.
            if (dia.DayOfWeek == DayOfWeek.Friday && efectivoSemana > 0)
            {
                _reloj.Ahora = Momento(dia, 17, 30);
                await conta.CrearManualAsync(new CrearPartidaRequest(dia, "Depósito del efectivo de la semana",
                    new() { new(cuentas[CuentasSistema.Bancos], efectivoSemana, 0), new(cuentas[CuentasSistema.Caja], 0, efectivoSemana) }), contador, ct);
                efectivoSemana = 0;
            }
            if (dia.Day == 1 || d == 0)
            {
                _reloj.Ahora = Momento(dia, 9, 0);
                foreach (var (cuenta, monto, concepto) in new[]
                         {
                             ("6101", 24_500m, "Planilla de sueldos"), ("6102", 6_500m, "Alquiler del local"),
                             ("6103", 1_350m, "Energía eléctrica, agua e internet"), ("6105", 900m, "Gastos varios de oficina")
                         })
                    await conta.CrearManualAsync(new CrearPartidaRequest(dia, $"{concepto} de {dia:MM/yyyy}",
                        new() { new(cuentas[cuenta], monto, 0), new(cuentas[CuentasSistema.Bancos], 0, monto) }), contador, ct);
            }
        }

        _log?.LogInformation("Datos de demostración listos: {Ventas} ventas.", ventasHechas);
        return true;
    }

    private async Task<List<int>> CrearVendedoresAsync(AppDbContext db, CancellationToken ct)
    {
        var nuevos = new[] { ("Carlos", "Méndez", "VEN-0101"), ("Lucía", "Ramírez", "VEN-0102"), ("Andrea", "Castillo", "VEN-0103") };
        foreach (var (nombre, apellido, codigo) in nuevos)
        {
            if (await db.Usuarios.AnyAsync(u => u.CodigoCorporativo == codigo, ct)) continue;
            db.Usuarios.Add(new Usuario
            {
                Nombre = nombre,
                Apellido = apellido,
                Username = $"{nombre} {apellido}",
                Email = $"{nombre.ToLowerInvariant()}.{Geografia.Normalizar(apellido)}@pedidos.local",
                CodigoCorporativo = codigo,
                Telefono = $"+5025{Entre(1000000, 9999999)}",
                // Sin contraseña (como un invitado): no puede iniciar sesión hasta que el admin le envíe la invitación.
                PasswordHash = UsuarioService.MarcaSinContrasena + Guid.NewGuid().ToString("N"),
                Rol = Roles.Vendedor,
                CreadoEn = _reloj.Ahora.UtcDateTime
            });
        }
        await db.SaveChangesAsync(ct);
        return await db.Usuarios.Where(u => u.Rol == Roles.Vendedor && u.Activo).Select(u => u.Id).ToListAsync(ct);
    }

    private sealed record ProductoCatalogo(int Id, string Codigo, decimal Costo);

    private async Task<List<ProductoCatalogo>> CargarCatalogoAsync(CancellationToken ct)
    {
        await using var db = _contexto();
        var costos = Catalogo.ToDictionary(p => p.Codigo, p => p.Costo);
        var lista = await db.Productos.Where(p => p.Activo).Select(p => new { p.Id, p.Codigo, p.CostoPromedio }).ToListAsync(ct);
        return lista.Select(p => new ProductoCatalogo(p.Id, p.Codigo,
            costos.TryGetValue(p.Codigo, out var c) ? c : Math.Max(1m, Math.Round(p.CostoPromedio, 2)))).ToList();
    }

    private List<LineaPedidoRequest> LineasAlAzar(List<ProductoCatalogo> catalogo, Dictionary<string, int> popularidad)
    {
        int Peso(ProductoCatalogo p) => popularidad.GetValueOrDefault(p.Codigo, 5);
        var total = catalogo.Sum(Peso);
        var elegidos = new HashSet<ProductoCatalogo>();
        var n = _azar.NextDouble() switch { < 0.6 => 1, < 0.9 => 2, _ => 3 };
        while (elegidos.Count < n)
        {
            var r = _azar.Next(total);
            foreach (var p in catalogo)
            {
                if (r < Peso(p)) { elegidos.Add(p); break; }
                r -= Peso(p);
            }
        }
        return elegidos.Select(p => new LineaPedidoRequest(p.Id, p.Costo > 2000 ? 1 : Entre(1, 3))).ToList();
    }

    /// <summary>Compra lo necesario para llegar a la existencia objetivo de cada producto y la recibe en bodega.</summary>
    private async Task ReponerAsync(AppDbContext db, ContabilidadService conta, DateOnly dia, List<ProductoCatalogo> catalogo,
        Dictionary<string, int> popularidad, List<int> proveedores, int compras, int bodega, bool inicial, CancellationToken ct)
    {
        var existencias = await db.Productos.AsNoTracking().ToDictionaryAsync(p => p.Id, p => p.Stock, ct);
        var lineas = new List<LineaOrdenRequest>();
        foreach (var p in catalogo)
        {
            var objetivo = popularidad.GetValueOrDefault(p.Codigo, 5) * (p.Costo > 2000 ? 3 : 7) + (inicial ? 5 : 0);
            var falta = objetivo - existencias.GetValueOrDefault(p.Id);
            if (falta <= 0) continue;
            // El costo varía ±6 % entre compras: así el costo promedio se mueve como en la realidad.
            var costo = Math.Round(p.Costo * (decimal)(0.94 + _azar.NextDouble() * 0.12), 2);
            lineas.Add(new LineaOrdenRequest(p.Id, falta, costo));
        }
        if (lineas.Count == 0 || proveedores.Count == 0) return;

        var servicio = new CompraService(db, conta, _reloj);
        foreach (var grupo in lineas.Chunk(8))
        {
            _reloj.Ahora = Momento(dia, 7, Entre(0, 30));
            var orden = await servicio.CrearAsync(new CrearOrdenRequest(Elegir(proveedores), grupo.ToList(), "Reposición semanal"), compras, ct);
            _reloj.Ahora = Momento(dia, 7, Entre(35, 59));
            await servicio.RecibirAsync(orden.Numero, new RecibirOrdenRequest($"A-{Entre(10000, 99999)}"), bodega, ct);
        }
    }

    private async Task AvanzarPipelineAsync(AppDbContext db, int id, int vendedor, DateOnly dia, int hora, DateOnly hoy,
        int admin, int contador, int bodega, CancellationToken ct)
    {
        var antiguedad = hoy.DayNumber - dia.DayNumber;
        var etapas = antiguedad switch
        {
            > 6 => 5,
            >= 4 => Entre(4, 5),
            >= 2 => Entre(2, 4),
            1 => Entre(1, 2),
            _ => Entre(0, 1)
        };
        var pipeline = new PipelineService(db, _reloj);
        var momento = Momento(dia, hora, 30);
        var limite = DateTimeOffset.UtcNow.AddMinutes(-5);
        for (var e = 0; e < etapas; e++)
        {
            momento = momento.AddHours(Entre(2, 20));
            if (momento > limite) break;
            _reloj.Ahora = momento;
            var (usuario, rol) = e switch
            {
                0 => (vendedor, Roles.Vendedor),
                1 => _azar.NextDouble() < 0.5 ? (admin, Roles.Admin) : (contador, Roles.Contador),
                _ => (bodega, Roles.Bodega)
            };
            if (rol == Roles.Contador && contador == admin) rol = Roles.Admin;
            if (rol == Roles.Bodega && bodega == admin) rol = Roles.Admin;
            await pipeline.AvanzarAsync(id, usuario, rol, null, ct);
        }
    }
}

/// <summary>Ejecuta el generador al arrancar la API (en segundo plano) si Demo:Generar es true.</summary>
public class GeneradorDemoHostedService : BackgroundService
{
    private readonly IServiceScopeFactory _scopes;
    private readonly IConfiguration _config;
    private readonly ILogger<GeneradorDemoHostedService> _log;

    public GeneradorDemoHostedService(IServiceScopeFactory scopes, IConfiguration config, ILogger<GeneradorDemoHostedService> log)
    {
        _scopes = scopes;
        _config = config;
        _log = log;
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        if (!_config.GetValue<bool>("Demo:Generar")) return;
        var dias = _config.GetValue("Demo:Dias", 120);
        try
        {
            using var scope = _scopes.CreateScope();
            var opciones = scope.ServiceProvider.GetRequiredService<DbContextOptions<AppDbContext>>();
            await new GeneradorDemo(() => new AppDbContext(opciones), _log).GenerarAsync(dias, stoppingToken);
        }
        catch (OperationCanceledException)
        {
            // La API se detuvo mientras generaba.
        }
        catch (Exception ex)
        {
            _log.LogError(ex, "No se pudieron generar los datos de demostración.");
        }
    }
}
