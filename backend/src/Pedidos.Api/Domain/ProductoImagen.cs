namespace Pedidos.Api.Domain;

/// <summary>
/// Foto del producto guardada en la BD (hasta <see cref="MaximoPorProducto"/> por producto). La de
/// <see cref="Orden"/> 0 es la principal: la que se ve en el catálogo.
/// </summary>
public class ProductoImagen
{
    public const int MaximoPorProducto = 5;
    public const int TamanoMaximo = 2 * 1024 * 1024;

    public int Id { get; set; }
    public int ProductoId { get; set; }
    public int Orden { get; set; }

    /// <summary>Se deduce de los bytes del archivo (no del nombre ni de lo que declare el navegador).</summary>
    public string ContentType { get; set; } = "image/jpeg";
    public byte[] Datos { get; set; } = Array.Empty<byte>();
    public int Tamano { get; set; }
    public DateTime CreadoEn { get; set; }
}
