namespace Pedidos.Api.Errors;

/// <summary>El recurso pedido no existe. Se traduce a 404 con el mensaje tal cual.</summary>
public class NoEncontradoException : Exception
{
    public NoEncontradoException(string message) : base(message) { }
}
