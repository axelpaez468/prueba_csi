namespace Pedidos.Api.Errors;

/// <summary>Violación de una regla de negocio. Se traduce a 400 con el mensaje tal cual.</summary>
public class BusinessRuleException : Exception
{
    public BusinessRuleException(string message) : base(message) { }
}
