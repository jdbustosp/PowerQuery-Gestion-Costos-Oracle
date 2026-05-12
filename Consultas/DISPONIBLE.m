let
    // =======================================================================
    // NOMBRE CONSULTA: DISPONIBLE_OPTIMIZADO
    // ESTRATEGIA: Uso de Buffer en memoria y evitar re-procesos.
    // =======================================================================

    // -----------------------------------------------------------------------
    // PASO 1: PREPARAR Y "BUFFERIZAR" EL PRESUPUESTO (V1)
    // -----------------------------------------------------------------------
    Source_Asegurado = ASEGURADO,

    // Agrupamos. Nota: Al incluir todos los niveles aquí, evitamos tener que buscarlos luego.
    Ppto_Agrupado = Table.Group(Source_Asegurado, {"Cod actividad", "Cod ins"}, {
        // Métricas V1
        {"Cant_Ppto", each List.Sum([Cantidad PPTO V1]), type nullable number},
        {"Total_Ppto", each List.Sum([VT PPTO V1]), type nullable number},
        {"Unitario_Ppto_Ref", each List.Average([#"V/U PPTO V1"]), type nullable number},

        // Jerarquía (Guardamos el primer valor encontrado para no perderlo)
        {"Paquete de Trabajo", each List.First([Paquete de Trabajo]), type nullable text},
        {"Cod CBS 1", each List.First([Cod CBS 1]), type nullable text},
        {"Cod CBS 2", each List.First([Cod CBS 2]), type nullable text},
        {"Cod CBS 3", each List.First([Cod CBS 3]), type nullable text},
        {"Cod CBS 4", each List.First([Cod CBS 4]), type nullable text},
        {"Nivel 1", each List.First([Nivel 1]), type nullable text},
        {"Nivel 2", each List.First([Nivel 2]), type nullable text},
        {"Nivel 3", each List.First([Nivel 3]), type nullable text},
        {"Nivel 4", each List.First([Nivel 4]), type nullable text},
        {"Actividad_Oficial", each List.First([Actividad]), type nullable text},
        {"Ins_Oficial", each List.First([Ins]), type nullable text},
        {"UM_Oficial", each List.First([U Medida]), type nullable text}
    }),

    // >>> TRUCO DE VELOCIDAD: Guardamos esta tabla en la RAM <<<
    Ppto_Memoria = Table.Buffer(Ppto_Agrupado),

    // -----------------------------------------------------------------------
    // PASO 2: PREPARAR LA EJECUCIÓN (DESDE EXCEL)
    // -----------------------------------------------------------------------
    Source_Comp = Excel.CurrentWorkbook(){[Name="COMPARATIVOS"]}[Content],

    // Tipos correctos
    Tipo_Comp = Table.TransformColumnTypes(Source_Comp,{
        {"Cod actividad", type text}, {"Cod ins", type text},
        {"Cantidad ppto (CC)", type number},
        {"Valor Total ppto (CC)", type number},
        {"V/U ppto (CC)", type number}
    }),

    // Limpieza de basura (Filas vacías o ceros)
    Filtro_Comp_Limpio = Table.SelectRows(Tipo_Comp, each ([#"Valor Total ppto (CC)"] <> null and [#"Valor Total ppto (CC)"] <> 0)),

    // Agrupamos para cálculo matemático (Suma de lo ejecutado por ítem)
    Comp_Agrupado = Table.Group(Filtro_Comp_Limpio, {"Cod actividad", "Cod ins"}, {
        {"Cant_Ejecutada_Total", each List.Sum([#"Cantidad ppto (CC)"]), type nullable number},
        {"Total_Ejecutado_Total", each List.Sum([#"Valor Total ppto (CC)"]), type nullable number}
    }),

    // -----------------------------------------------------------------------
    // PASO 3: RAMA A - CÁLCULO DE "POR ADJUDICAR"
    // (Usamos el Ppto_Memoria que ya tiene la jerarquía, ¡más rápido!)
    // -----------------------------------------------------------------------
    Merge_Saldos = Table.NestedJoin(Ppto_Memoria, {"Cod actividad", "Cod ins"}, Comp_Agrupado, {"Cod actividad", "Cod ins"}, "EJECUCION", JoinKind.LeftOuter),
    Expand_Saldos = Table.ExpandTableColumn(Merge_Saldos, "EJECUCION", {"Cant_Ejecutada_Total", "Total_Ejecutado_Total"}, {"Cant_Ejecutada_Total", "Total_Ejecutado_Total"}),

    // Reemplazo de nulos y Matemáticas
    Transform_Math = Table.TransformColumns(Expand_Saldos, {
        {"Cant_Ejecutada_Total", each if _ = null then 0 else _, type number},
        {"Total_Ejecutado_Total", each if _ = null then 0 else _, type number}
    }),

    Add_Pendientes = Table.AddColumn(Transform_Math, "Total_Pendiente", each [Total_Ppto] - [Total_Ejecutado_Total], type number),
    Add_Cant_Pend  = Table.AddColumn(Add_Pendientes, "Cant_Pendiente", each [Cant_Ppto] - [Cant_Ejecutada_Total], type number),
    Add_Unit_Pend  = Table.AddColumn(Add_Cant_Pend, "Unitario_Pendiente", each if [Cant_Pendiente] > 0.0001 then [Total_Pendiente] / [Cant_Pendiente] else [Unitario_Ppto_Ref], type number),

    // Filtro Final "Por Adjudicar"
    Filtro_PorAdjudicar = Table.SelectRows(Add_Unit_Pend, each [Total_Pendiente] > 1),

    // Selección y Renombre (Manteniendo la jerarquía que ya tenemos)
    Select_Rama_Pend = Table.SelectColumns(Filtro_PorAdjudicar,
        {"Paquete de Trabajo", "Cod CBS 1", "Cod CBS 2", "Cod CBS 3", "Cod CBS 4", "Nivel 1", "Nivel 2", "Nivel 3", "Nivel 4", "Actividad_Oficial", "Ins_Oficial", "UM_Oficial", "Cod actividad", "Cod ins", "Cant_Pendiente", "Unitario_Pendiente", "Total_Pendiente"}
    ),

    Rename_Rama_Pend = Table.RenameColumns(Select_Rama_Pend, {
        {"Cant_Pendiente", "Cantidad ppto (CC)"},
        {"Unitario_Pendiente", "V/U ppto (CC)"},
        {"Total_Pendiente", "Valor Total ppto (CC)"},
        {"Actividad_Oficial", "Actividad"},
        {"Ins_Oficial", "Ins"},
        {"UM_Oficial", "U Medida"}
    }),

    Final_Rama_Pend = Table.AddColumn(Table.AddColumn(Rename_Rama_Pend, "Tipo", each "Por adjudicar"), "# CC - Comparativo", each "Por adjudicar"),

    // -----------------------------------------------------------------------
    // PASO 4: RAMA B - PREPARAR "ADJUDICADO"
    // (Aquí sí cruzamos con Ppto_Memoria para traer la jerarquía faltante)
    // -----------------------------------------------------------------------
    Select_Rama_Real = Table.SelectColumns(Filtro_Comp_Limpio,
        {"Paquete de Trabajo", "Cod actividad", "Cod ins", "Cantidad ppto (CC)", "V/U ppto (CC)", "Valor Total ppto (CC)", "# CC - Comparativo"}
    ),

    // Cruzamos los datos reales con el presupuesto en memoria para traer niveles
    Merge_Jerarquia_Real = Table.NestedJoin(Select_Rama_Real, {"Cod actividad", "Cod ins"}, Ppto_Memoria, {"Cod actividad", "Cod ins"}, "JERARQUIA", JoinKind.LeftOuter),

    Expand_Jerarquia_Real = Table.ExpandTableColumn(Merge_Jerarquia_Real, "JERARQUIA",
        {"Cod CBS 1", "Cod CBS 2", "Cod CBS 3", "Cod CBS 4", "Nivel 1", "Nivel 2", "Nivel 3", "Nivel 4", "Actividad_Oficial", "Ins_Oficial", "UM_Oficial"},
        {"Cod CBS 1", "Cod CBS 2", "Cod CBS 3", "Cod CBS 4", "Nivel 1", "Nivel 2", "Nivel 3", "Nivel 4", "Actividad", "Ins", "U Medida"}
    ),

    Final_Rama_Real = Table.AddColumn(Expand_Jerarquia_Real, "Tipo", each "Adjudicado"),

    // -----------------------------------------------------------------------
    // PASO 5: UNIÓN FINAL (Super Rápida)
    // -----------------------------------------------------------------------
    Union_Rapida = Table.Combine({Final_Rama_Real, Final_Rama_Pend}),

    // Limpieza final de seguridad y ordenamiento
    Filtro_Final = Table.SelectRows(Union_Rapida, each ([#"Valor Total ppto (CC)"] <> 0 and [#"Valor Total ppto (CC)"] <> null and [Cod actividad] <> null)),

    Orden_Definitivo = Table.ReorderColumns(Filtro_Final, {
        "Paquete de Trabajo",
        "Cod CBS 1", "Nivel 1", "Cod CBS 2", "Nivel 2", "Cod CBS 3", "Nivel 3", "Cod CBS 4", "Nivel 4",
        "Cod actividad", "Actividad", "Cod ins", "Ins", "U Medida",
        "Cantidad ppto (CC)", "V/U ppto (CC)", "Valor Total ppto (CC)",
        "Tipo", "# CC - Comparativo"
    }),

    Limpiar_Cols = Table.RemoveColumns(Orden_Definitivo,{"U Medida"})
in
    Limpiar_Cols
