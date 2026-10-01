namespace Pedidos.Api.Services.Erp;

public record DepartamentoDto(string Nombre, string Iso, List<string> Municipios);

/// <summary>
/// Los 22 departamentos de Guatemala y sus 340 municipios. Es la única fuente: la API valida contra esta lista y el
/// frontend la descarga para los selectores. Los nombres coinciden con los del mapa (geoBoundaries).
/// </summary>
public static class Geografia
{
    public static readonly IReadOnlyList<DepartamentoDto> Departamentos = new List<DepartamentoDto>
    {
        new("Alta Verapaz", "GT-AV", new() { "Cobán", "Santa Cruz Verapaz", "San Cristóbal Verapaz", "Tactic", "Tamahú", "Tucurú", "Panzós", "Senahú", "San Pedro Carchá", "San Juan Chamelco", "Lanquín", "Santa María Cahabón", "Chisec", "Chahal", "Fray Bartolomé de las Casas", "Santa Catalina La Tinta", "Raxruhá" }),
        new("Baja Verapaz", "GT-BV", new() { "Salamá", "San Miguel Chicaj", "Rabinal", "Cubulco", "Granados", "Santa Cruz El Chol", "San Jerónimo", "Purulhá" }),
        new("Chimaltenango", "GT-CM", new() { "Chimaltenango", "San José Poaquil", "San Martín Jilotepeque", "San Juan Comalapa", "Santa Apolonia", "Tecpán Guatemala", "Patzún", "San Miguel Pochuta", "Patzicía", "Santa Cruz Balanyá", "Acatenango", "San Pedro Yepocapa", "San Andrés Itzapa", "Parramos", "Zaragoza", "El Tejar" }),
        new("Chiquimula", "GT-CQ", new() { "Chiquimula", "San José La Arada", "San Juan Ermita", "Jocotán", "Camotán", "Olopa", "Esquipulas", "Concepción Las Minas", "Quezaltepeque", "San Jacinto", "Ipala" }),
        new("El Progreso", "GT-PR", new() { "Guastatoya", "Morazán", "San Agustín Acasaguastlán", "San Cristóbal Acasaguastlán", "El Jícaro", "Sansare", "Sanarate", "San Antonio La Paz" }),
        new("Escuintla", "GT-ES", new() { "Escuintla", "Santa Lucía Cotzumalguapa", "La Democracia", "Siquinalá", "Masagua", "Tiquisate", "La Gomera", "Guanagazapa", "San José", "Iztapa", "Palín", "San Vicente Pacaya", "Nueva Concepción", "Sipacate" }),
        new("Guatemala", "GT-GU", new() { "Guatemala", "Santa Catarina Pinula", "San José Pinula", "San José del Golfo", "Palencia", "Chinautla", "San Pedro Ayampuc", "Mixco", "San Pedro Sacatepéquez", "San Juan Sacatepéquez", "San Raymundo", "Chuarrancho", "Fraijanes", "Amatitlán", "Villa Nueva", "Villa Canales", "San Miguel Petapa" }),
        new("Huehuetenango", "GT-HU", new() { "Huehuetenango", "Chiantla", "Malacatancito", "Cuilco", "Nentón", "San Pedro Necta", "Jacaltenango", "San Pedro Soloma", "San Ildefonso Ixtahuacán", "Santa Bárbara", "La Libertad", "La Democracia", "San Miguel Acatán", "San Rafael La Independencia", "Todos Santos Cuchumatán", "San Juan Atitán", "Santa Eulalia", "San Mateo Ixtatán", "Colotenango", "San Sebastián Huehuetenango", "Tectitán", "Concepción Huista", "San Juan Ixcoy", "San Antonio Huista", "San Sebastián Coatán", "Santa Cruz Barillas", "Aguacatán", "San Rafael Petzal", "San Gaspar Ixchil", "Santiago Chimaltenango", "Santa Ana Huista", "Unión Cantinil", "Petatán" }),
        new("Izabal", "GT-IZ", new() { "Puerto Barrios", "Livingston", "El Estor", "Morales", "Los Amates" }),
        new("Jalapa", "GT-JA", new() { "Jalapa", "San Pedro Pinula", "San Luis Jilotepeque", "San Manuel Chaparrón", "San Carlos Alzatate", "Monjas", "Mataquescuintla" }),
        new("Jutiapa", "GT-JU", new() { "Jutiapa", "El Progreso", "Santa Catarina Mita", "Agua Blanca", "Asunción Mita", "Yupiltepeque", "Atescatempa", "Jerez", "El Adelanto", "Zapotitlán", "Comapa", "Jalpatagua", "Conguaco", "Moyuta", "Pasaco", "San José Acatempa", "Quesada" }),
        new("Petén", "GT-PE", new() { "Flores", "San José", "San Benito", "San Andrés", "La Libertad", "San Francisco", "Santa Ana", "Dolores", "San Luis", "Sayaxché", "Melchor de Mencos", "Poptún", "Las Cruces", "El Chal" }),
        new("Quetzaltenango", "GT-QZ", new() { "Quetzaltenango", "Salcajá", "Olintepeque", "San Carlos Sija", "Sibilia", "Cabricán", "Cajolá", "San Miguel Sigüilá", "San Juan Ostuncalco", "San Mateo", "Concepción Chiquirichapa", "San Martín Sacatepéquez", "Almolonga", "Cantel", "Huitán", "Zunil", "Colomba", "San Francisco La Unión", "El Palmar", "Coatepeque", "Génova", "Flores Costa Cuca", "La Esperanza", "Palestina de Los Altos" }),
        new("Quiché", "GT-QC", new() { "Santa Cruz del Quiché", "Chiché", "Chinique", "Zacualpa", "Chajul", "Chichicastenango", "Patzité", "San Antonio Ilotenango", "San Pedro Jocopilas", "Cunén", "San Juan Cotzal", "Joyabaj", "Nebaj", "San Andrés Sajcabajá", "Uspantán", "Sacapulas", "San Bartolomé Jocotenango", "Canillá", "Chicamán", "Ixcán", "Pachalum" }),
        new("Retalhuleu", "GT-RE", new() { "Retalhuleu", "San Sebastián", "Santa Cruz Muluá", "San Martín Zapotitlán", "San Felipe", "San Andrés Villa Seca", "Champerico", "Nuevo San Carlos", "El Asintal" }),
        new("Sacatepéquez", "GT-SA", new() { "Antigua Guatemala", "Jocotenango", "Pastores", "Sumpango", "Santo Domingo Xenacoj", "Santiago Sacatepéquez", "San Bartolomé Milpas Altas", "San Lucas Sacatepéquez", "Santa Lucía Milpas Altas", "Magdalena Milpas Altas", "Santa María de Jesús", "Ciudad Vieja", "San Miguel Dueñas", "Alotenango", "San Antonio Aguas Calientes", "Santa Catarina Barahona" }),
        new("San Marcos", "GT-SM", new() { "San Marcos", "San Pedro Sacatepéquez", "San Antonio Sacatepéquez", "Comitancillo", "San Miguel Ixtahuacán", "Concepción Tutuapa", "Tacaná", "Sibinal", "Tajumulco", "Tejutla", "San Rafael Pie de la Cuesta", "Nuevo Progreso", "El Tumbador", "El Rodeo", "Malacatán", "Catarina", "Ayutla", "Ocós", "San Pablo", "El Quetzal", "La Reforma", "Pajapita", "Ixchiguán", "San José Ojetenam", "San Cristóbal Cucho", "Sipacapa", "Esquipulas Palo Gordo", "Río Blanco", "San Lorenzo", "La Blanca" }),
        new("Santa Rosa", "GT-SR", new() { "Cuilapa", "Barberena", "Santa Rosa de Lima", "Casillas", "San Rafael Las Flores", "Oratorio", "San Juan Tecuaco", "Chiquimulilla", "Taxisco", "Santa María Ixhuatán", "Guazacapán", "Santa Cruz Naranjo", "Pueblo Nuevo Viñas", "Nueva Santa Rosa" }),
        new("Sololá", "GT-SO", new() { "Sololá", "San José Chacayá", "Santa María Visitación", "Santa Lucía Utatlán", "Nahualá", "Santa Catarina Ixtahuacán", "Santa Clara La Laguna", "Concepción", "San Andrés Semetabaj", "Panajachel", "Santa Catarina Palopó", "San Antonio Palopó", "San Lucas Tolimán", "Santa Cruz La Laguna", "San Pablo La Laguna", "San Marcos La Laguna", "San Juan La Laguna", "San Pedro La Laguna", "Santiago Atitlán" }),
        new("Suchitepéquez", "GT-SU", new() { "Mazatenango", "Cuyotenango", "San Francisco Zapotitlán", "San Bernardino", "San José El Ídolo", "Santo Domingo Suchitepéquez", "San Lorenzo", "Samayac", "San Pablo Jocopilas", "San Antonio Suchitepéquez", "San Miguel Panán", "San Gabriel", "Chicacao", "Patulul", "Santa Bárbara", "San Juan Bautista", "Santo Tomás La Unión", "Zunilito", "Pueblo Nuevo", "Río Bravo", "San José La Máquina" }),
        new("Totonicapán", "GT-TO", new() { "Totonicapán", "San Cristóbal Totonicapán", "San Francisco El Alto", "San Andrés Xecul", "Momostenango", "Santa María Chiquimula", "Santa Lucía La Reforma", "San Bartolo" }),
        new("Zacapa", "GT-ZA", new() { "Zacapa", "Estanzuela", "Río Hondo", "Gualán", "Teculután", "Usumatlán", "Cabañas", "San Diego", "La Unión", "Huité", "San Jorge" }),
    };

    private static readonly Dictionary<string, DepartamentoDto> PorNombre =
        Departamentos.ToDictionary(d => Normalizar(d.Nombre), StringComparer.Ordinal);

    /// <summary>Sin tildes, sin espacios de más y en minúsculas, para comparar lo que escribe el usuario.</summary>
    public static string Normalizar(string texto) =>
        new string(texto.Trim().Normalize(System.Text.NormalizationForm.FormD)
                .Where(c => System.Globalization.CharUnicodeInfo.GetUnicodeCategory(c) != System.Globalization.UnicodeCategory.NonSpacingMark)
                .ToArray())
            .ToLowerInvariant();

    /// <summary>Devuelve los nombres oficiales (con tildes) o null si el departamento o el municipio no existen o no coinciden.</summary>
    public static (string Departamento, string Municipio)? Validar(string? departamento, string? municipio)
    {
        if (string.IsNullOrWhiteSpace(departamento) || string.IsNullOrWhiteSpace(municipio)) return null;
        if (!PorNombre.TryGetValue(Normalizar(departamento), out var d)) return null;
        var m = d.Municipios.FirstOrDefault(x => Normalizar(x) == Normalizar(municipio));
        return m is null ? null : (d.Nombre, m);
    }
}
