let
    // --- PASO 1: UNIÓN DE TABLAS ---
    Fuente = Table.Combine({ASEGURADO, COMPARATIVOS, DISPONIBLE}),

    // --- PASO 2: BUFFER DEL CLASIFICADOR ---
    FilasClasificador = Table.SelectRows(Fuente, each [Clasificador] <> null and Text.Trim([Clasificador]) <> ""),
    MaestroBuffer = Table.Buffer(Table.Distinct(Table.SelectColumns(FilasClasificador, {"Ins", "Clasificador"}), {"Ins"})),

    Cruce = Table.NestedJoin(Fuente, {"Ins"}, MaestroBuffer, {"Ins"}, "Aux", JoinKind.LeftOuter),
    Expandido = Table.ExpandTableColumn(Cruce, "Aux", {"Clasificador"}, {"Clas_Sugerido"}),

    BaseLimpia = Table.RenameColumns(
        Table.RemoveColumns(
            Table.AddColumn(Expandido, "Clasificador_Final", each [Clasificador] ?? [Clas_Sugerido], type text),
            {"Clasificador", "Clas_Sugerido"}
        ),
        {{"Clasificador_Final", "Clasificador"}}
    ),

    // --- PASO 3: LIMPIEZA DE TEXTOS ---
    ConTipoUpper = Table.AddColumn(BaseLimpia, "TipoUpper", each if [Tipo] = null then "" else Text.Upper(Text.Trim([Tipo])), type text),
    ConInsLimpio = Table.AddColumn(ConTipoUpper, "InsLimpio", each if [Ins] = null then "" else Text.Trim([Ins]), type text),

    // --- PASO 4: OPTIMIZACIÓN EXTREMA DE VELOCIDAD (Uso de Join en lugar de List.Contains) ---
    // A. Filtramos solo las filas que son "Reales"
    FilasReales = Table.SelectRows(ConInsLimpio, each
        Text.Contains([TipoUpper], "CONTRATO") or Text.Contains([TipoUpper], "ORDEN DE COMPRA") or
        Text.Contains([TipoUpper], "CAJA MENOR") or Text.Contains([TipoUpper], "SERVICIO PUBLICO") or
        Text.Contains([TipoUpper], "GESTION RECURSOS HUMANOS")
    ),

    // B. Creamos una tabla única de esos 'Ins' y les ponemos una marca de verdadero (true)
    TablaInsReales = Table.Distinct(Table.SelectColumns(FilasReales, {"InsLimpio"})),
    MarcaReales = Table.AddColumn(TablaInsReales, "EsGrupoMixto", each true, type logical),
    BufferMarca = Table.Buffer(MarcaReales),

    // C. Cruzamos esta marca con la tabla principal (esto es instantáneo comparado con la lista)
    CruceReales = Table.NestedJoin(ConInsLimpio, {"InsLimpio"}, BufferMarca, {"InsLimpio"}, "AuxReales", JoinKind.LeftOuter),
    BaseConMarca = Table.ExpandTableColumn(CruceReales, "AuxReales", {"EsGrupoMixto"}, {"EsGrupoMixto"}),

    // --- PASO 5: PROYECCIÓN EXACTA ---
    AgregarVTProyectado = Table.AddColumn(BaseConMarca, "VT PROYECTADO COLSUBSIDIO", each
        let
            T = [TipoUpper],
            TieneReales = [EsGrupoMixto] = true, // Si el cruce trajo 'true', pertenece al Escenario A
            EsReal = Text.Contains(T, "CONTRATO") or Text.Contains(T, "ORDEN DE COMPRA") or Text.Contains(T, "CAJA MENOR") or Text.Contains(T, "SERVICIO PUBLICO") or Text.Contains(T, "GESTION RECURSOS HUMANOS"),

            Resultado =
                if TieneReales then
                    // ----------------------------------------------------------------
                    // ESCENARIO A (Imágenes 3 y 4): GRUPO MIXTO
                    // ----------------------------------------------------------------
                    if EsReal then [VT Asegurado]
                    else if Text.Contains(T, "ADJUDICAR") then [#"Valor Total ppto (CC)"]
                    else null
                else
                    // ----------------------------------------------------------------
                    // ESCENARIO B (Imágenes 1 y 2): GRUPO PURO (Solo CC)
                    // ----------------------------------------------------------------
                    if Text.Contains(T, "CC") or Text.Contains(T, "C.C") or Text.Contains(T, "ADJUDICADO") then [VT CC]
                    else if Text.Contains(T, "ADJUDICAR") then [#"Valor Total ppto (CC)"]
                    else null
        in
            Resultado,
        type number
    ),

    // Limpiamos las columnas de apoyo
    PasoFinal = Table.RemoveColumns(AgregarVTProyectado, {"TipoUpper", "InsLimpio", "EsGrupoMixto"})

in
    PasoFinal
