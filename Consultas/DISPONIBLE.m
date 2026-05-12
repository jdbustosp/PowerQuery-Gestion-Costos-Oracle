let
    // =======================================================================
    // NOMBRE CONSULTA: DISPONIBLE
    // ESTRATEGIA:
    // - Usa ConfigProyecto para elegir si calcula contra PPTO V1 o PPTO V2.
    // - Cruza por Paquete de Trabajo + Cod actividad + Cod ins para no mezclar paquetes.
    // =======================================================================

    Source_Asegurado = ASEGURADO,
    VersionPresupuesto = Text.Upper(Text.From(ConfigProyecto[VersionPresupuestoDisponible])),
    ColCantidadPpto = if VersionPresupuesto = "V2" then "Cantidad PPTO V2" else "Cantidad PPTO V1",
    ColTotalPpto = if VersionPresupuesto = "V2" then "VT PPTO V2" else "VT PPTO V1",
    ColUnitarioPpto = if VersionPresupuesto = "V2" then "V/U PPTO V2" else "V/U PPTO V1",

    SumColumn = (tbl as table, col as text) as nullable number =>
        if Table.HasColumns(tbl, col) then List.Sum(List.RemoveNulls(Table.Column(tbl, col))) else null,

    AvgColumn = (tbl as table, col as text) as nullable number =>
        let
            vals = if Table.HasColumns(tbl, col) then List.RemoveNulls(Table.Column(tbl, col)) else {}
        in
            if List.Count(vals) = 0 then null else List.Average(vals),

    FirstColumn = (tbl as table, col as text) as any =>
        if Table.HasColumns(tbl, col) and Table.RowCount(tbl) > 0 then List.First(Table.Column(tbl, col)) else null,

    // -----------------------------------------------------------------------
    // PASO 1: PREPARAR Y BUFFERIZAR EL PRESUPUESTO SEGUN CONFIGURACION
    // -----------------------------------------------------------------------
    Ppto_Agrupado = Table.Group(Source_Asegurado, {"Paquete de Trabajo", "Cod actividad", "Cod ins"}, {
        {"Cant_Ppto", (t) => SumColumn(t, ColCantidadPpto), type nullable number},
        {"Total_Ppto", (t) => SumColumn(t, ColTotalPpto), type nullable number},
        {"Unitario_Ppto_Ref", (t) => AvgColumn(t, ColUnitarioPpto), type nullable number},

        {"Cod CBS 1", (t) => FirstColumn(t, "Cod CBS 1"), type nullable text},
        {"Cod CBS 2", (t) => FirstColumn(t, "Cod CBS 2"), type nullable text},
        {"Cod CBS 3", (t) => FirstColumn(t, "Cod CBS 3"), type nullable text},
        {"Cod CBS 4", (t) => FirstColumn(t, "Cod CBS 4"), type nullable text},
        {"Nivel 1", (t) => FirstColumn(t, "Nivel 1"), type nullable text},
        {"Nivel 2", (t) => FirstColumn(t, "Nivel 2"), type nullable text},
        {"Nivel 3", (t) => FirstColumn(t, "Nivel 3"), type nullable text},
        {"Nivel 4", (t) => FirstColumn(t, "Nivel 4"), type nullable text},
        {"Actividad_Oficial", (t) => FirstColumn(t, "Actividad"), type nullable text},
        {"Ins_Oficial", (t) => FirstColumn(t, "Ins"), type nullable text},
        {"UM_Oficial", (t) => FirstColumn(t, "U Medida"), type nullable text}
    }),

    Ppto_Memoria = Table.Buffer(Ppto_Agrupado),

    // -----------------------------------------------------------------------
    // PASO 2: PREPARAR LA EJECUCION DESDE EXCEL
    // -----------------------------------------------------------------------
    Source_Comp = Excel.CurrentWorkbook(){[Name="COMPARATIVOS"]}[Content],

    Tipo_Comp = Table.TransformColumnTypes(Source_Comp,{
        {"Paquete de Trabajo", type text},
        {"Cod actividad", type text},
        {"Cod ins", type text},
        {"Cantidad ppto (CC)", type number},
        {"Valor Total ppto (CC)", type number},
        {"V/U ppto (CC)", type number}
    }),

    Filtro_Comp_Limpio = Table.SelectRows(Tipo_Comp, each ([#"Valor Total ppto (CC)"] <> null and [#"Valor Total ppto (CC)"] <> 0)),

    Comp_Agrupado = Table.Group(Filtro_Comp_Limpio, {"Paquete de Trabajo", "Cod actividad", "Cod ins"}, {
        {"Cant_Ejecutada_Total", each List.Sum([#"Cantidad ppto (CC)"]), type nullable number},
        {"Total_Ejecutado_Total", each List.Sum([#"Valor Total ppto (CC)"]), type nullable number}
    }),

    // -----------------------------------------------------------------------
    // PASO 3: RAMA POR ADJUDICAR
    // -----------------------------------------------------------------------
    Merge_Saldos = Table.NestedJoin(
        Ppto_Memoria,
        {"Paquete de Trabajo", "Cod actividad", "Cod ins"},
        Comp_Agrupado,
        {"Paquete de Trabajo", "Cod actividad", "Cod ins"},
        "EJECUCION",
        JoinKind.LeftOuter
    ),
    Expand_Saldos = Table.ExpandTableColumn(Merge_Saldos, "EJECUCION", {"Cant_Ejecutada_Total", "Total_Ejecutado_Total"}, {"Cant_Ejecutada_Total", "Total_Ejecutado_Total"}),

    Transform_Math = Table.TransformColumns(Expand_Saldos, {
        {"Cant_Ejecutada_Total", each if _ = null then 0 else _, type number},
        {"Total_Ejecutado_Total", each if _ = null then 0 else _, type number}
    }),

    Add_Pendientes = Table.AddColumn(Transform_Math, "Total_Pendiente", each [Total_Ppto] - [Total_Ejecutado_Total], type number),
    Add_Cant_Pend = Table.AddColumn(Add_Pendientes, "Cant_Pendiente", each [Cant_Ppto] - [Cant_Ejecutada_Total], type number),
    Add_Unit_Pend = Table.AddColumn(Add_Cant_Pend, "Unitario_Pendiente", each if [Cant_Pendiente] > 0.0001 then [Total_Pendiente] / [Cant_Pendiente] else [Unitario_Ppto_Ref], type number),

    Filtro_PorAdjudicar = Table.SelectRows(Add_Unit_Pend, each [Total_Pendiente] > 1),

    Select_Rama_Pend = Table.SelectColumns(Filtro_PorAdjudicar, {
        "Paquete de Trabajo",
        "Cod CBS 1", "Cod CBS 2", "Cod CBS 3", "Cod CBS 4",
        "Nivel 1", "Nivel 2", "Nivel 3", "Nivel 4",
        "Actividad_Oficial", "Ins_Oficial", "UM_Oficial",
        "Cod actividad", "Cod ins",
        "Cant_Pendiente", "Unitario_Pendiente", "Total_Pendiente"
    }, MissingField.UseNull),

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
    // PASO 4: RAMA ADJUDICADO
    // -----------------------------------------------------------------------
    Select_Rama_Real = Table.SelectColumns(Filtro_Comp_Limpio, {
        "Paquete de Trabajo", "Cod actividad", "Cod ins", "Cantidad ppto (CC)", "V/U ppto (CC)", "Valor Total ppto (CC)", "# CC - Comparativo"
    }, MissingField.UseNull),

    Merge_Jerarquia_Real = Table.NestedJoin(
        Select_Rama_Real,
        {"Paquete de Trabajo", "Cod actividad", "Cod ins"},
        Ppto_Memoria,
        {"Paquete de Trabajo", "Cod actividad", "Cod ins"},
        "JERARQUIA",
        JoinKind.LeftOuter
    ),

    Expand_Jerarquia_Real = Table.ExpandTableColumn(Merge_Jerarquia_Real, "JERARQUIA",
        {"Cod CBS 1", "Cod CBS 2", "Cod CBS 3", "Cod CBS 4", "Nivel 1", "Nivel 2", "Nivel 3", "Nivel 4", "Actividad_Oficial", "Ins_Oficial", "UM_Oficial"},
        {"Cod CBS 1", "Cod CBS 2", "Cod CBS 3", "Cod CBS 4", "Nivel 1", "Nivel 2", "Nivel 3", "Nivel 4", "Actividad", "Ins", "U Medida"}
    ),

    Final_Rama_Real = Table.AddColumn(Expand_Jerarquia_Real, "Tipo", each "Adjudicado"),

    // -----------------------------------------------------------------------
    // PASO 5: UNION FINAL
    // -----------------------------------------------------------------------
    Union_Rapida = Table.Combine({Final_Rama_Real, Final_Rama_Pend}),

    Filtro_Final = Table.SelectRows(Union_Rapida, each ([#"Valor Total ppto (CC)"] <> 0 and [#"Valor Total ppto (CC)"] <> null and [Cod actividad] <> null)),

    Orden_Definitivo = Table.ReorderColumns(Filtro_Final, {
        "Paquete de Trabajo",
        "Cod CBS 1", "Nivel 1", "Cod CBS 2", "Nivel 2", "Cod CBS 3", "Nivel 3", "Cod CBS 4", "Nivel 4",
        "Cod actividad", "Actividad", "Cod ins", "Ins", "U Medida",
        "Cantidad ppto (CC)", "V/U ppto (CC)", "Valor Total ppto (CC)",
        "Tipo", "# CC - Comparativo"
    }, MissingField.UseNull),

    Limpiar_Cols = Table.RemoveColumns(Orden_Definitivo,{"U Medida"})
in
    Limpiar_Cols
