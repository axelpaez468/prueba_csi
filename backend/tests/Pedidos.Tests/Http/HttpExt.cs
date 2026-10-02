using System.Net;
using System.Net.Http.Json;
using System.Text;
using System.Text.Json;

namespace Pedidos.Tests.Http;

/// <summary>Atajos para las pruebas HTTP: enviar JSON, leer la respuesta y fallar con el cuerpo a la vista.</summary>
public static class HttpExt
{
    public static Task<HttpResponseMessage> PostJson(this HttpClient http, string url, object? cuerpo = null) =>
        http.PostAsJsonAsync(url, cuerpo ?? new { }, ApiEnVivo.Json);

    public static Task<HttpResponseMessage> PutJson(this HttpClient http, string url, object? cuerpo = null) =>
        http.PutAsJsonAsync(url, cuerpo ?? new { }, ApiEnVivo.Json);

    public static Task<HttpResponseMessage> PostTexto(this HttpClient http, string url, string cuerpo, string tipo = "application/json") =>
        http.PostAsync(url, new StringContent(cuerpo, Encoding.UTF8, tipo));

    public static async Task<JsonElement> Json(this HttpResponseMessage r)
    {
        var texto = await r.Content.ReadAsStringAsync();
        return string.IsNullOrWhiteSpace(texto) ? default : JsonDocument.Parse(texto).RootElement.Clone();
    }

    /// <summary>Verifica el código y devuelve el JSON; si no coincide, el mensaje incluye lo que respondió la API.</summary>
    public static async Task<JsonElement> Esperar(this Task<HttpResponseMessage> peticion, HttpStatusCode esperado)
    {
        using var r = await peticion;
        var texto = await r.Content.ReadAsStringAsync();
        Assert.True(r.StatusCode == esperado,
            $"{r.RequestMessage?.Method} {r.RequestMessage?.RequestUri?.PathAndQuery}: se esperaba {(int)esperado} y llegó {(int)r.StatusCode} {texto}");
        return string.IsNullOrWhiteSpace(texto) ? default : JsonDocument.Parse(texto).RootElement.Clone();
    }

    public static Task<JsonElement> Ok(this Task<HttpResponseMessage> p) => p.Esperar(HttpStatusCode.OK);
    public static Task<JsonElement> Creado(this Task<HttpResponseMessage> p) => p.Esperar(HttpStatusCode.Created);

    /// <summary>400 con el mensaje de error esperado (en español, para el usuario).</summary>
    public static async Task<string> Rechazo(this Task<HttpResponseMessage> p, string contiene)
    {
        var j = await p.Esperar(HttpStatusCode.BadRequest);
        var mensaje = j.GetProperty("error").GetString()!;
        Assert.Contains(contiene, mensaje, StringComparison.OrdinalIgnoreCase);
        return mensaje;
    }

    public static int Int(this JsonElement j, string p) => j.GetProperty(p).GetInt32();
    public static decimal Dec(this JsonElement j, string p) => j.GetProperty(p).GetDecimal();
    public static string Str(this JsonElement j, string p) => j.GetProperty(p).GetString()!;

    /// <summary>Lanza todas las peticiones a la vez (lo más simultáneo posible) y devuelve los códigos.</summary>
    public static async Task<List<(HttpStatusCode Status, string Cuerpo)>> Simultaneas(int veces, Func<int, Task<HttpResponseMessage>> peticion)
    {
        using var largada = new SemaphoreSlim(0);
        var tareas = Enumerable.Range(0, veces).Select(async i =>
        {
            await largada.WaitAsync();
            using var r = await peticion(i);
            return (r.StatusCode, await r.Content.ReadAsStringAsync());
        }).ToList();
        largada.Release(veces);
        return (await Task.WhenAll(tareas)).ToList();
    }
}
