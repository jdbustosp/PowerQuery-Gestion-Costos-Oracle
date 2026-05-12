let
    // 1. CARGAR DATOS
    Origen = Excel.CurrentWorkbook(){[Name="PRESUPUESTO"]}[Content],

    // 2. LIMPIEZA Y TIPOS
    TipoCambiado = Table.TransformColumnTypes(Origen,{
        {"Cod CBS", type text},
        {"Descripción", type text},
        {"UM", type text},
        {"Cant", type number},
        {"VrUni", type number},
        {"Total", type number}
    }),
    TextoLimpio = Table.TransformColumns(TipoCambiado,{{"Cod CBS", each if _ = null then null else Text.Trim(_), type text}}),

    TipoJerarquia = Text.Upper(Text.From(ConfigProyecto[TipoJerarquia])),

    AddMetricasFinales = (table as table) as table =>
        let
            CalcVrUni = Table.AddColumn(table, "V/U PPTO V1", each if [#"Cantidad PPTO V1"] <> null and [#"Cantidad PPTO V1"] <> 0 then [#"VT PPTO V1"] / [#"Cantidad PPTO V1"] else 0, type number),
            AddCantV2 = Table.AddColumn(CalcVrUni, "Cantidad PPTO V2", each [#"Cantidad PPTO V1"], type number),
            AddVUV2 = Table.AddColumn(AddCantV2, "V/U PPTO V2", each [#"V/U PPTO V1"], type number),
            AddVTV2 = Table.AddColumn(AddVUV2, "VT PPTO V2", each [#"VT PPTO V1"], type number),
            AddTipo = Table.AddColumn(AddVTV2, "Tipo", each "PRESUPUESTO V1", type text)
        in
            AddTipo,

    OrdenColumnas = (table as table) as table =>
        Table.SelectColumns(table, {
            "Paquete de Trabajo",
            "Cod CBS 1", "Cod CBS 2", "Cod CBS 3", "Cod CBS 4", "Cod actividad", "Cod ins",
            "Nivel 1", "Nivel 2", "Nivel 3", "Nivel 4", "Actividad", "Ins",
            "Tipo", "Cantidad PPTO V1", "V/U PPTO V1", "VT PPTO V1",
            "Cantidad PPTO V2", "V/U PPTO V2", "VT PPTO V2"
        }, MissingField.UseNull),

    ProcesarJerarquiaLarga = (tabla as table) as table =>
        let
            Add_Paquete = Table.AddColumn(tabla, "Paquete_Temp", each
                if [Cod CBS] <> null
                   and [Cod CBS] <> "Gran Total"
                   and not Text.Contains([Cod CBS], "-")
                then [Descripción]
                else null
            ),
            Fill_Paquete = Table.FillDown(Add_Paquete,{"Paquete_Temp"}),
            Rename_Paquete = Table.RenameColumns(Fill_Paquete,{{"Paquete_Temp", "Paquete de Trabajo"}}),

            AgregarNivel = Table.AddColumn(Rename_Paquete, "NivelCalculado", each
                if [Cod CBS] = null then null
                else if not Text.Contains([Cod CBS], "-") then 0
                else if Text.Length([Cod CBS]) < 15 then 6
                else if Text.EndsWith([Cod CBS], "-00-00-00-0000-000") then 1
                else if Text.EndsWith([Cod CBS], "-00-00-0000-000") then 2
                else if Text.EndsWith([Cod CBS], "-00-0000-000") then 3
                else if Text.EndsWith([Cod CBS], "-0000-000") then 4
                else 5
            ),

            Col_C1 = Table.AddColumn(AgregarNivel, "C1", each if [NivelCalculado]=1 then [Cod CBS] else null),
            Col_D1 = Table.AddColumn(Col_C1, "D1", each if [NivelCalculado]=1 then [Descripción] else null),
            Col_C2 = Table.AddColumn(Col_D1, "C2", each if [NivelCalculado]=2 then [Cod CBS] else null),
            Col_D2 = Table.AddColumn(Col_C2, "D2", each if [NivelCalculado]=2 then [Descripción] else null),
            Col_C3 = Table.AddColumn(Col_D2, "C3", each if [NivelCalculado]=3 then [Cod CBS] else null),
            Col_D3 = Table.AddColumn(Col_C3, "D3", each if [NivelCalculado]=3 then [Descripción] else null),
            Col_C4 = Table.AddColumn(Col_D3, "C4", each if [NivelCalculado]=4 then [Cod CBS] else null),
            Col_D4 = Table.AddColumn(Col_C4, "D4", each if [NivelCalculado]=4 then [Descripción] else null),
            Col_C5 = Table.AddColumn(Col_D4, "C5", each if [NivelCalculado]=5 then [Cod CBS] else null),
            Col_D5 = Table.AddColumn(Col_C5, "D5", each if [NivelCalculado]=5 then [Descripción] else null),
            Col_UM5= Table.AddColumn(Col_D5, "UM5", each if [NivelCalculado]=5 then [UM] else null),

            RellenarTodo = Table.FillDown(Col_UM5, {"C1","D1", "C2","D2", "C3","D3", "C4","D4", "C5","D5","UM5"}),
            FiltrarInsumos = Table.SelectRows(RellenarTodo, each ([NivelCalculado] = 6) and ([Cod CBS] <> null) and ([Cod CBS] <> "Gran Total")),

            Agrupar = Table.Group(FiltrarInsumos,
                {"Paquete de Trabajo", "C1", "D1", "C2", "D2", "C3", "D3", "C4", "D4", "C5", "D5", "UM5", "Cod CBS", "Descripción", "UM"},
                {{"Cantidad PPTO V1", each List.Sum([Cant]), type number}, {"VT PPTO V1", each List.Sum([Total]), type number}}
            ),

            Nivel1 = Table.AddColumn(Agrupar, "Nivel 1", each [C1] & " - " & [D1]),
            Nivel2 = Table.AddColumn(Nivel1, "Nivel 2", each [C2] & " - " & [D2]),
            Nivel3 = Table.AddColumn(Nivel2, "Nivel 3", each [C3] & " - " & [D3]),
            Nivel4 = Table.AddColumn(Nivel3, "Nivel 4", each [C4] & " - " & [D4]),
            Activ = Table.AddColumn(Nivel4, "Actividad", each [C5] & " - " & [D5] & " (" & (if [UM5]=null then "" else [UM5]) & ")"),
            Insumo = Table.AddColumn(Activ, "Ins", each [Descripción] & " (" & [UM] & ")"),

            Renombrar = Table.RenameColumns(Insumo,{
                {"C1", "Cod CBS 1"},
                {"C2", "Cod CBS 2"},
                {"C3", "Cod CBS 3"},
                {"C4", "Cod CBS 4"},
                {"C5", "Cod actividad"},
                {"Cod CBS", "Cod ins"}
            }),
            ConMetricas = AddMetricasFinales(Renombrar),
            Orden = OrdenColumnas(ConMetricas)
        in
            Orden,

    ProcesarJerarquiaCorta = (tabla as table) as table =>
        let
            Add_Paquete = Table.AddColumn(tabla, "Paquete_Temp", each
                if [Cod CBS] <> null
                   and [Cod CBS] <> "Gran Total"
                   and not Text.Contains([Cod CBS], "-")
                then [Descripción]
                else null
            ),
            Fill_Paquete = Table.FillDown(Add_Paquete,{"Paquete_Temp"}),
            Rename_Paquete = Table.RenameColumns(Fill_Paquete,{{"Paquete_Temp", "Paquete de Trabajo"}}),

            AgregarNivel = Table.AddColumn(Rename_Paquete, "NivelCalculado", each
                if [Cod CBS] = null then null
                else if not Text.Contains([Cod CBS], "-") then 0
                else if Text.EndsWith([Cod CBS], "-00-000") then 1
                else if Text.EndsWith([Cod CBS], "-000") then 2
                else if Text.Length([Cod CBS]) > 0
                    and List.Contains({"0","1","2","3","4","5","6","7","8","9"}, Text.Start([Cod CBS], 1))
                    and Text.Length([Cod CBS]) < 11 then 3
                else 4
            ),

            Col_C1 = Table.AddColumn(AgregarNivel, "C1", each if [NivelCalculado]=1 then [Cod CBS] else null),
            Col_D1 = Table.AddColumn(Col_C1, "D1", each if [NivelCalculado]=1 then [Descripción] else null),
            Col_C2 = Table.AddColumn(Col_D1, "C2", each if [NivelCalculado]=2 then [Cod CBS] else null),
            Col_D2 = Table.AddColumn(Col_C2, "D2", each if [NivelCalculado]=2 then [Descripción] else null),
            Col_C3 = Table.AddColumn(Col_D2, "C3", each if [NivelCalculado]=3 then [Cod CBS] else null),
            Col_D3 = Table.AddColumn(Col_C3, "D3", each if [NivelCalculado]=3 then [Descripción] else null),
            Col_UM3= Table.AddColumn(Col_D3, "UM3", each if [NivelCalculado]=3 then [UM] else null),

            RellenarTodo = Table.FillDown(Col_UM3, {"C1","D1", "C2","D2", "C3","D3","UM3"}),
            FiltrarInsumos = Table.SelectRows(RellenarTodo, each ([NivelCalculado] = 4) and ([Cod CBS] <> null) and ([Cod CBS] <> "Gran Total")),

            Agrupar = Table.Group(FiltrarInsumos,
                {"Paquete de Trabajo", "C1", "D1", "C2", "D2", "C3", "D3", "UM3", "Cod CBS", "Descripción", "UM"},
                {{"Cantidad PPTO V1", each List.Sum([Cant]), type number}, {"VT PPTO V1", each List.Sum([Total]), type number}}
            ),

            Nivel1 = Table.AddColumn(Agrupar, "Nivel 1", each [C1] & " - " & [D1]),
            Nivel2 = Table.AddColumn(Nivel1, "Nivel 2", each [C2] & " - " & [D2]),
            Nivel3 = Table.AddColumn(Nivel2, "Nivel 3", each null, type nullable text),
            Nivel4 = Table.AddColumn(Nivel3, "Nivel 4", each null, type nullable text),
            CodCBS3 = Table.AddColumn(Nivel4, "Cod CBS 3", each null, type nullable text),
            CodCBS4 = Table.AddColumn(CodCBS3, "Cod CBS 4", each null, type nullable text),
            Activ = Table.AddColumn(CodCBS4, "Actividad", each [C3] & " - " & [D3] & " (" & (if [UM3]=null then "" else [UM3]) & ")"),
            Insumo = Table.AddColumn(Activ, "Ins", each [Descripción] & " (" & [UM] & ")"),

            Renombrar = Table.RenameColumns(Insumo,{
                {"C1", "Cod CBS 1"},
                {"C2", "Cod CBS 2"},
                {"C3", "Cod actividad"},
                {"Cod CBS", "Cod ins"}
            }),
            ConMetricas = AddMetricasFinales(Renombrar),
            Orden = OrdenColumnas(ConMetricas)
        in
            Orden,

    Resultado = if TipoJerarquia = "CORTA"
        then ProcesarJerarquiaCorta(TextoLimpio)
        else ProcesarJerarquiaLarga(TextoLimpio)
in
    Resultado
