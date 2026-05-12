let
    // ------------------------------------------------------------------
    // PASO 1: CARGAR LA TABLA INTERNA "COMPARATIVOS"
    // ------------------------------------------------------------------
    Fuente = Excel.CurrentWorkbook(){[Name="COMPARATIVOS"]}[Content],

    // Aseguramos tipo texto para el cruce
    TipoCambiado = Table.TransformColumnTypes(Fuente,{{"Cod actividad", type text}}),

    // ------------------------------------------------------------------
    // PASO 2: PREPARAR Y LIMPIAR LA TABLA "ASEGURADO"
    // ------------------------------------------------------------------
    Origen_Asegurado = ASEGURADO,

    // Seleccionamos SOLO las columnas de CBS y Niveles
    Asegurado_Select = Table.SelectColumns(Origen_Asegurado, {
        "Cod CBS 1", "Cod CBS 2", "Cod CBS 3", "Cod CBS 4",
        "Cod actividad",
        "Nivel 1", "Nivel 2", "Nivel 3", "Nivel 4"
    }),

    // Aseguramos tipo texto en la llave y quitamos duplicados
    Asegurado_Tipo = Table.TransformColumnTypes(Asegurado_Select,{{"Cod actividad", type text}}),
    Asegurado_Unico = Table.Distinct(Asegurado_Tipo, {"Cod actividad"}),

    // ------------------------------------------------------------------
    // PASO 3: HACER EL CRUCE (MERGE)
    // ------------------------------------------------------------------
    Cruce = Table.NestedJoin(
        TipoCambiado, {"Cod actividad"},
        Asegurado_Unico, {"Cod actividad"},
        "Datos_Asegurado",
        JoinKind.LeftOuter
    ),

    // ------------------------------------------------------------------
    // PASO 4: EXPANDIR CBS Y NIVELES
    // ------------------------------------------------------------------
    Expandido = Table.ExpandTableColumn(Cruce, "Datos_Asegurado",
        {"Cod CBS 1", "Cod CBS 2", "Cod CBS 3", "Cod CBS 4", "Nivel 1", "Nivel 2", "Nivel 3", "Nivel 4"},
        {"Cod CBS 1", "Cod CBS 2", "Cod CBS 3", "Cod CBS 4", "Nivel 1", "Nivel 2", "Nivel 3", "Nivel 4"}
    ),

    // ------------------------------------------------------------------
    // PASO 5: FILTRAR NULOS (Nuevo)
    // ------------------------------------------------------------------
    // Eliminamos las filas donde "VT CC" esté vacío (null)
    Filtrado_Nulos = Table.SelectRows(Expandido, each ([VT CC] <> null)),

    // ------------------------------------------------------------------
    // PASO 6: AGREGAR COLUMNA "TIPO" (Nuevo)
    // ------------------------------------------------------------------
    // Creamos la columna con el valor fijo "CC"
    Columna_Tipo = Table.AddColumn(Filtrado_Nulos, "Tipo", each "CC"),

    // ------------------------------------------------------------------
    // PASO 7: SELECCIONAR Y ORDENAR (Actualizado)
    // ------------------------------------------------------------------
    // Eliminé las columnas "Cantidad ppto (CC)", "V/U ppto (CC)" y "Valor Total ppto (CC)".
    // Agregué la columna "Tipo" al final.
    ColumnasFinales = Table.SelectColumns(Columna_Tipo, {
        "Paquete de Trabajo",
        "Cod CBS 1", "Nivel 1",
        "Cod CBS 2", "Nivel 2",
        "Cod CBS 3", "Nivel 3",
        "Cod CBS 4", "Nivel 4",
        "Cod actividad", "Actividad",
        "Cod ins", "Ins",
        "# OC / Contrato",
        "Nombre contratista",
        "Cantidad CC", "V/U CC", "VT CC",
        "# CC - Comparativo",
        "Clasificador",
        "Tipo"
    })
in
    ColumnasFinales
