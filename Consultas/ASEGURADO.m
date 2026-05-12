let
    // ===============================================================
    // 1. FUNCIONES DE LIMPIEZA
    // ===============================================================
    FixHeaders = (table as table) as table =>
        let
            Promoted = if Table.ColumnNames(table){0} = "Column1" then Table.PromoteHeaders(table, [PromoteAllScalars=true]) else table,
            CleanNames = Table.TransformColumnNames(Promoted, Text.Trim)
        in
            CleanNames,

    CleanKey = (val) => if val = null then "" else Text.Upper(Text.Clean(Text.Trim(Text.From(val)))),
    ToNumberSafe = (val) => let n = try Number.From(val) otherwise 0 in if n = null then 0 else n,
    TipoJerarquia = Text.Upper(Text.From(ConfigProyecto[TipoJerarquia])),
    EsJerarquiaCorta = TipoJerarquia = "CORTA",

    // Lógica Anti-Eco para limpiar nombres duplicados tipo "(ML) (ML)"
    CleanString = (code, rawName) =>
        let
            c = if code = null then "" else Text.Trim(Text.From(code)),
            n = if rawName = null then "SIN NOMBRE" else Text.Trim(Text.From(rawName)),
            // 1. Quitar el código del inicio si existe
            NameNoCode = if c <> "" and Text.StartsWith(n, c) then Text.Trim(Text.Range(n, Text.Length(c))) else n,
            // 2. Quitar guiones iniciales
            NameClean = Text.TrimStart(NameNoCode, {"-", " "}),
            // 3. LOGICA ANTI-REPETICIÓN
            Parts = Text.Split(NameClean, " "),
            Cnt = List.Count(Parts),
            FixedName = if Cnt >= 2 and (Parts{Cnt-1} = Parts{Cnt-2}) and Text.StartsWith(Parts{Cnt-1}, "(") then
                            Text.Combine(List.RemoveLastN(Parts, 1), " ")
                        else
                            NameClean
        in
            c & " - " & FixedName,

    // ===============================================================
    // 2. PREPARAR TABLAS BASE
    // ===============================================================

    // --- PRESUPUESTO ---
    Src_Ppto = PRESUPUESTO,
    Clean_Ppto = Table.TransformColumns(Src_Ppto, {
        {"Paquete de Trabajo", CleanKey}, {"Cod actividad", CleanKey}, {"Cod ins", CleanKey},
        {"Cantidad PPTO V1", ToNumberSafe}, {"VT PPTO V1", ToNumberSafe}, {"V/U PPTO V1", ToNumberSafe}
    }),

    // --- ASEGURADO ---
    Src_Asegurado = FixHeaders(SP_Fuentes[ASEGURADO]),
    Renamed_Aseg = Table.RenameColumns(Src_Asegurado,{
        {"Cod CBS", "Cod actividad"}, {"Descripción", "Actividad"},
        {"Articulo", "Cod ins"}, {"Descripción2", "Ins"}
    }, MissingField.Ignore),
    Clean_Aseg = Table.TransformColumns(Renamed_Aseg, {
        {"Registro", CleanKey}, {"Cod ins", CleanKey}, {"Paquete de Trabajo", CleanKey}, {"Cod actividad", CleanKey}
    }),
    Filtered_Aseg = Table.SelectRows(Clean_Aseg, each [Proceso] <> "COSTOS DISTRIBUIBLES" and [Proceso] <> "TRANSFERENCIA"),

    // --- CONTRATO ---
    Src_Contrato = FixHeaders(SP_Fuentes[CONTRATOS]),
    Clean_Contrato = Table.TransformColumns(Src_Contrato, {
        {"Orden", CleanKey}, {"Articulo", CleanKey}, {"Paquete de trabajo", CleanKey}, {"CBS", CleanKey},
        {"Cantidad corte", ToNumberSafe}, {"Valor Recepcion corte", ToNumberSafe}
    }),

    // --- OC ---
    Src_OC = FixHeaders(SP_Fuentes[COMPRAS]),
    Clean_OC = Table.TransformColumns(Src_OC, {
        {"Orden", CleanKey}, {"Articulo", CleanKey}, {"Paquete de trabajo", CleanKey}, {"CBS", CleanKey},
        {"Cantidad recepcion", ToNumberSafe}, {"Valor Recepcion", ToNumberSafe}
    }),

    // ===============================================================
    // 3. DICCIONARIO UNIVERSAL
    // ===============================================================

    // >>> ACTIVIDADES <<<
    Dict_Act_1 = Table.SelectColumns(Clean_Ppto, {"Cod actividad", "Actividad"}),
    Dict_Act_2 = Table.SelectColumns(Filtered_Aseg, {"Cod actividad", "Actividad"}),
    Dict_Act_3 = Table.RenameColumns(Table.SelectColumns(Clean_Contrato, {"CBS", "Titulo"}), {{"CBS", "Cod actividad"}, {"Titulo", "Actividad"}}, MissingField.Ignore),
    Dict_Act_4 = Table.RenameColumns(Table.SelectColumns(Clean_OC, {"CBS", "Titulo"}), {{"CBS", "Cod actividad"}, {"Titulo", "Actividad"}}, MissingField.Ignore),

    Union_Act = Table.Combine({Dict_Act_1, Dict_Act_2, Dict_Act_3, Dict_Act_4}),
    Distinct_Act = Table.Distinct(Table.SelectRows(Union_Act, each [Cod actividad] <> null and [Cod actividad] <> ""), {"Cod actividad"}),
    Master_Act = Table.Buffer(Table.AddColumn(Distinct_Act, "Actividad_Limpia", each CleanString([Cod actividad], [Actividad]))),

    // >>> INSUMOS <<<
    Dict_Ins_1 = Table.SelectColumns(Clean_Ppto, {"Cod ins", "Ins"}),
    Dict_Ins_2 = Table.SelectColumns(Filtered_Aseg, {"Cod ins", "Ins"}),
    Dict_Ins_3 = Table.RenameColumns(Table.SelectColumns(Clean_Contrato, {"Articulo", "Titulo"}), {{"Articulo", "Cod ins"}, {"Titulo", "Ins"}}, MissingField.Ignore),
    Dict_Ins_4 = Table.RenameColumns(Table.SelectColumns(Clean_OC, {"Articulo", "Titulo"}), {{"Articulo", "Cod ins"}, {"Titulo", "Ins"}}, MissingField.Ignore),

    Union_Ins = Table.Combine({Dict_Ins_1, Dict_Ins_2, Dict_Ins_3, Dict_Ins_4}),
    Distinct_Ins = Table.Distinct(Table.SelectRows(Union_Ins, each [Cod ins] <> null and [Cod ins] <> ""), {"Cod ins"}),
    Master_Ins = Table.Buffer(Table.AddColumn(Distinct_Ins, "Ins_Limpio", each
        let
            Raw = if [Ins] = null then "" else Text.Trim(Text.From([Ins])),
            Cleaned = if Text.EndsWith(Raw, ")") and Text.Contains(Raw, "(") then Raw else Raw
        in Cleaned
    )),

    // ===============================================================
    // 4. AGRUPAR (BUFFERS)
    // ===============================================================

    Grouped_Ppto = Table.Buffer(Table.Group(Clean_Ppto, {"Paquete de Trabajo", "Cod actividad", "Cod ins"}, {
        {"Cant_P1", each List.Sum([#"Cantidad PPTO V1"]), type number},
        {"VU_P1", each List.Max([#"V/U PPTO V1"]), type number},
        {"VT_P1", each List.Sum([#"VT PPTO V1"]), type number},
        {"Cod CBS 1", each List.Max([Cod CBS 1]), type text},
        {"Cod CBS 2", each List.Max([Cod CBS 2]), type text},
        {"Cod CBS 3", each List.Max([Cod CBS 3]), type text},
        {"Cod CBS 4", each List.Max([Cod CBS 4]), type text},
        {"Nivel 1", each List.Max([Nivel 1]), type text},
        {"Nivel 2", each List.Max([Nivel 2]), type text},
        {"Nivel 3", each List.Max([Nivel 3]), type text},
        {"Nivel 4", each List.Max([Nivel 4]), type text}
    })),

    Grouped_Contrato = Table.Buffer(Table.Group(Clean_Contrato, {"Orden", "Articulo", "Paquete de trabajo", "CBS"}, {
        {"Tit_Ct", each List.Max([Titulo]), type text},
        {"Raz_Ct", each List.Max([Razon Social]), type text},
        {"Cant_Ct", each List.Sum([Cantidad corte]), type number},
        {"Val_Ct", each List.Sum([Valor Recepcion corte]), type number}
    })),

    Grouped_OC = Table.Buffer(Table.Group(Clean_OC, {"Orden", "Articulo", "Paquete de trabajo", "CBS"}, {
        {"Tit_OC", each List.Max([Titulo]), type text},
        {"Raz_OC", each List.Max([Razon Social]), type text},
        {"Cant_OC", each List.Sum([#"Cantidad recepcion"]), type number},
        {"Val_OC", each List.Sum([#"Valor Recepcion"]), type number}
    })),

    // ===============================================================
    // 5. UNIONES EN CASCADA
    // ===============================================================

    // Join 1: Asegurado + Contrato
    Join1 = Table.NestedJoin(Filtered_Aseg, {"Registro", "Cod ins", "Paquete de Trabajo", "Cod actividad"}, Grouped_Contrato, {"Orden", "Articulo", "Paquete de trabajo", "CBS"}, "DATA_CT", JoinKind.FullOuter),
    Exp1 = Table.ExpandTableColumn(Join1, "DATA_CT", {"Orden", "Articulo", "Paquete de trabajo", "CBS", "Tit_Ct", "Raz_Ct", "Cant_Ct", "Val_Ct"}, {"O_Ct", "A_Ct", "P_Ct", "C_Ct", "Tit_Ct", "Raz_Ct", "Cant_Ct", "Val_Ct"}),

    Key1 = Table.AddColumn(Exp1, "K_Reg", each if [Registro]<>null then [Registro] else [O_Ct]),
    Key2 = Table.AddColumn(Key1, "K_Ins", each if [Cod ins]<>null then [Cod ins] else [A_Ct]),
    Key3 = Table.AddColumn(Key2, "K_Paq", each if [Paquete de Trabajo]<>null then [Paquete de Trabajo] else [P_Ct]),
    Key4 = Table.AddColumn(Key3, "K_Act", each if [Cod actividad]<>null then [Cod actividad] else [C_Ct]),

    // Join 2: + OC
    Join2 = Table.NestedJoin(Key4, {"K_Reg", "K_Ins", "K_Paq", "K_Act"}, Grouped_OC, {"Orden", "Articulo", "Paquete de trabajo", "CBS"}, "DATA_OC", JoinKind.FullOuter),
    Exp2 = Table.ExpandTableColumn(Join2, "DATA_OC", {"Orden", "Articulo", "Paquete de trabajo", "CBS", "Tit_OC", "Raz_OC", "Cant_OC", "Val_OC"}, {"O_OC", "A_OC", "P_OC", "C_OC", "Tit_OC", "Raz_OC", "Cant_OC", "Val_OC"}),

    Key5 = Table.AddColumn(Exp2, "K2_Reg", each if [K_Reg]<>null then [K_Reg] else [O_OC]),
    Key6 = Table.AddColumn(Key5, "K2_Ins", each if [K_Ins]<>null then [K_Ins] else [A_OC]),
    Key7 = Table.AddColumn(Key6, "K2_Paq", each if [K_Paq]<>null then [K_Paq] else [P_OC]),
    Key8 = Table.AddColumn(Key7, "K2_Act", each if [K_Act]<>null then [K_Act] else [C_OC]),

    // Join 3: + Ppto (AQUÍ ESTABA EL ERROR, AHORA CORREGIDO)
    Join3 = Table.NestedJoin(Key8, {"K2_Paq", "K2_Act", "K2_Ins"}, Grouped_Ppto, {"Paquete de Trabajo", "Cod actividad", "Cod ins"}, "DATA_PPTO", JoinKind.FullOuter),
    // Expandimos explícitamente los Niveles para que no falle después
    Exp3 = Table.ExpandTableColumn(Join3, "DATA_PPTO",
        {"Cant_P1", "VU_P1", "VT_P1", "Paquete de Trabajo", "Cod actividad", "Cod ins",
         "Cod CBS 1", "Cod CBS 2", "Cod CBS 3", "Cod CBS 4",
         "Nivel 1", "Nivel 2", "Nivel 3", "Nivel 4"},
        {"Cant_P1", "VU_P1", "VT_P1", "P_P", "C_P", "I_P",
         "Cod CBS 1", "Cod CBS 2", "Cod CBS 3", "Cod CBS 4",
         "Nivel 1", "Nivel 2", "Nivel 3", "Nivel 4"}),

    // ===============================================================
    // 6. CÁLCULO DE VALORES
    // ===============================================================
    Final_Paquete = Table.AddColumn(Exp3, "Final_Paquete", each if [K2_Paq]<>null then [K2_Paq] else [P_P]),
    Final_CodAct  = Table.AddColumn(Final_Paquete, "Final_CodAct", each if [K2_Act]<>null then [K2_Act] else [C_P]),
    Final_CodIns  = Table.AddColumn(Final_CodAct, "Final_CodIns", each if [K2_Ins]<>null then [K2_Ins] else [I_P]),
    Final_Reg     = Table.AddColumn(Final_CodIns, "Final_Reg", each [K2_Reg]),

    Final_Razon     = Table.AddColumn(Final_Reg, "Final_Razon", each if [Raz_Ct]<>null then [Raz_Ct] else if [Raz_OC]<>null then [Raz_OC] else try [Razon Social] otherwise null),
    Final_Titulo    = Table.AddColumn(Final_Razon, "Final_Titulo", each if [Tit_Ct]<>null then [Tit_Ct] else if [Tit_OC]<>null then [Tit_OC] else try [Titulo] otherwise null),
    Final_Proceso   = Table.AddColumn(Final_Titulo, "Final_Proceso", each if [Proceso]<>null then [Proceso] else if [O_Ct]<>null then "CONTRATO" else if [O_OC]<>null then "ORDEN DE COMPRA" else "PRESUPUESTO"),

    Val_Ppto1_C   = Table.AddColumn(Final_Proceso, "Final_Cant_P1", each if [Final_Proceso]="PRESUPUESTO" then [Cant_P1] else null),
    Val_Ppto1_V   = Table.AddColumn(Val_Ppto1_C, "Final_VT_P1", each if [Final_Proceso]="PRESUPUESTO" then [VT_P1] else null),
    Val_Ppto1_U   = Table.AddColumn(Val_Ppto1_V, "Final_VU_P1", each if [Final_Proceso]="PRESUPUESTO" then [VU_P1] else null),
    Val_Corte_C   = Table.AddColumn(Val_Ppto1_U, "Final_Cant_Corte", each if [Cant_Ct]<>null then [Cant_Ct] else if [Cant_OC]<>null then [Cant_OC] else 0),
    Val_Corte_V   = Table.AddColumn(Val_Corte_C, "Final_Val_Corte", each if [Val_Ct]<>null then [Val_Ct] else if [Val_OC]<>null then [Val_OC] else 0),
    Val_P2_C = Table.AddColumn(Val_Corte_V, "Final_Cant_P2", each if [Proceso]="PRESUPUESTO" then ToNumberSafe([Cantidad]) else 0),
    Val_P2_V = Table.AddColumn(Val_P2_C, "Final_VT_P2", each if [Proceso]="PRESUPUESTO" then ToNumberSafe([#"V.r Total"]) else 0),
    Val_As_C = Table.AddColumn(Val_P2_V, "Final_Cant_As", each if List.Contains({"GESTION RECURSOS HUMANOS","CAJA MENOR","CONTRATO","ORDEN DE COMPRA","SERVICIO PUBLICO"}, [Proceso]) then ToNumberSafe([Cantidad]) else 0),
    Val_As_V = Table.AddColumn(Val_As_C, "Final_VT_As", each if List.Contains({"GESTION RECURSOS HUMANOS","CAJA MENOR","CONTRATO","ORDEN DE COMPRA","SERVICIO PUBLICO"}, [Proceso]) then ToNumberSafe([#"V.r Total"]) else 0),
    Val_De_C = Table.AddColumn(Val_As_V, "Final_Cant_De", each if [Proceso]="DESCUENTOS" then ToNumberSafe([Cantidad]) else 0),
    Val_De_V = Table.AddColumn(Val_De_C, "Final_VT_De", each if [Proceso]="DESCUENTOS" then ToNumberSafe([#"V.r Total"]) else 0),

    // ===============================================================
    // 7. AGRUPACIÓN MAESTRA
    // ===============================================================
    Grouped_Master = Table.Group(Val_De_V,
        {"Final_Paquete", "Final_CodAct", "Final_CodIns", "Final_Razon", "Final_Titulo", "Final_Proceso", "Final_Reg",
         "Cod CBS 1", "Cod CBS 2", "Cod CBS 3", "Cod CBS 4", "Nivel 1", "Nivel 2", "Nivel 3", "Nivel 4"},
        {
            {"Cantidad PPTO V1", each List.Max([Final_Cant_P1]), type nullable number},
            {"V/U PPTO V1", each List.Max([Final_VU_P1]), type nullable number},
            {"VT PPTO V1", each List.Max([Final_VT_P1]), type nullable number},
            {"Cantidad corte", each List.Max([Final_Cant_Corte]), type nullable number},
            {"Valor Recepcion corte", each List.Max([Final_Val_Corte]), type nullable number},
            {"Cantidad PPTO V2", each List.Sum([Final_Cant_P2]), type nullable number},
            {"VT PPTO V2", each List.Sum([Final_VT_P2]), type nullable number},
            {"Cantidad Asegurado", each List.Sum([Final_Cant_As]), type nullable number},
            {"VT Asegurado", each List.Sum([Final_VT_As]), type nullable number},
            {"Cantidad Descuento", each List.Sum([Final_Cant_De]), type nullable number},
            {"VT Descuento", each List.Sum([Final_VT_De]), type nullable number}
        }
    ),

    Calc_VU_P2 = Table.AddColumn(Grouped_Master, "V/U PPTO V2", each if [Cantidad PPTO V2] <> null and [Cantidad PPTO V2] <> 0 then [VT PPTO V2]/[Cantidad PPTO V2] else 0, type nullable number),

    // ===============================================================
    // 8. ENRIQUECIMIENTO
    // ===============================================================
    Join_Act = Table.NestedJoin(Calc_VU_P2, {"Final_CodAct"}, Master_Act, {"Cod actividad"}, "Ref_A", JoinKind.LeftOuter),
    Exp_Act  = Table.ExpandTableColumn(Join_Act, "Ref_A", {"Actividad_Limpia"}, {"Actividad"}),

    Join_Ins = Table.NestedJoin(Exp_Act, {"Final_CodIns"}, Master_Ins, {"Cod ins"}, "Ref_I", JoinKind.LeftOuter),
    Exp_Ins  = Table.ExpandTableColumn(Join_Ins, "Ref_I", {"Ins_Limpio"}, {"Ins"}),

    Fill_Nulls = Table.TransformColumns(Exp_Ins, {
        {"Actividad", each if _ = null then "SIN NOMBRE (VERIFICAR CÓDIGO)" else _, type text},
        {"Ins", each if _ = null then "" else _, type text}
    }),

    // ===============================================================
    // 9. NIVELES Y CBS
    // ===============================================================
    Dict_N1 = Table.Buffer(Table.Distinct(Table.SelectColumns(Src_Ppto, {"Cod CBS 1", "Nivel 1"}), {"Cod CBS 1"})),
    Dict_N2 = Table.Buffer(Table.Distinct(Table.SelectColumns(Src_Ppto, {"Cod CBS 2", "Nivel 2"}), {"Cod CBS 2"})),
    Dict_N3 = Table.Buffer(Table.Distinct(Table.SelectColumns(Src_Ppto, {"Cod CBS 3", "Nivel 3"}), {"Cod CBS 3"})),
    Dict_N4 = Table.Buffer(Table.Distinct(Table.SelectColumns(Src_Ppto, {"Cod CBS 4", "Nivel 4"}), {"Cod CBS 4"})),

    Fill_CBS = Table.AddColumn(Fill_Nulls, "Calc_CBS", each
        let
            CurrentCode = [Final_CodAct],
            Parts = if CurrentCode <> null then Text.Split(CurrentCode, "-") else {},
            Count = List.Count(Parts),
            NewC1 = if Count > 0 then if EsJerarquiaCorta then Parts{0} & "-00-000" else Parts{0} & "-00-00-00-0000-000" else null,
            NewC2 = if Count > 1 then if EsJerarquiaCorta then Parts{0} & "-" & Parts{1} & "-000" else Parts{0} & "-" & Parts{1} & "-00-00-0000-000" else null,
            NewC3 = if EsJerarquiaCorta then null else if Count > 2 then Parts{0} & "-" & Parts{1} & "-" & Parts{2} & "-00-0000-000" else null,
            NewC4 = if EsJerarquiaCorta then null else if Count > 3 then Parts{0} & "-" & Parts{1} & "-" & Parts{2} & "-" & Parts{3} & "-0000-000" else null
        in
            [
                C1 = if [Cod CBS 1] = null or [Cod CBS 1] = "" then NewC1 else [Cod CBS 1],
                C2 = if [Cod CBS 2] = null or [Cod CBS 2] = "" then NewC2 else [Cod CBS 2],
                C3 = if [Cod CBS 3] = null or [Cod CBS 3] = "" then NewC3 else [Cod CBS 3],
                C4 = if [Cod CBS 4] = null or [Cod CBS 4] = "" then NewC4 else [Cod CBS 4]
            ]
    ),
    Expanded_CBS = Table.ExpandRecordColumn(Fill_CBS, "Calc_CBS", {"C1", "C2", "C3", "C4"}, {"New_CBS1", "New_CBS2", "New_CBS3", "New_CBS4"}),

    Join_N1 = Table.NestedJoin(Expanded_CBS, {"New_CBS1"}, Dict_N1, {"Cod CBS 1"}, "R1", JoinKind.LeftOuter),
    Join_N2 = Table.NestedJoin(Join_N1, {"New_CBS2"}, Dict_N2, {"Cod CBS 2"}, "R2", JoinKind.LeftOuter),
    Join_N3 = Table.NestedJoin(Join_N2, {"New_CBS3"}, Dict_N3, {"Cod CBS 3"}, "R3", JoinKind.LeftOuter),
    Join_N4 = Table.NestedJoin(Join_N3, {"New_CBS4"}, Dict_N4, {"Cod CBS 4"}, "R4", JoinKind.LeftOuter),

    Final_Filter = Table.SelectRows(Join_N4, each [Final_Paquete] <> "CCAMBIOS SIN LINEAS"),

    Calculated_Levels = Table.AddColumn(Final_Filter, "Levels_Final", each [
        N1 = if [Nivel 1] <> null then [Nivel 1] else try [R1]{0}[Nivel 1] otherwise null,
        N2 = if [Nivel 2] <> null then [Nivel 2] else try [R2]{0}[Nivel 2] otherwise null,
        N3 = if EsJerarquiaCorta then null else if [Nivel 3] <> null then [Nivel 3] else try [R3]{0}[Nivel 3] otherwise null,
        TempN4 = if [Nivel 4] <> null then [Nivel 4] else try [R4]{0}[Nivel 4] otherwise null,
        N4 = if EsJerarquiaCorta then null else if TempN4 = null then [New_CBS4] & " - OTROS" else TempN4
    ]),

    Expanded_Levels = Table.ExpandRecordColumn(Calculated_Levels, "Levels_Final", {"N1", "N2", "N3", "N4"}),
    Calc_VU_Desc = Table.AddColumn(Expanded_Levels, "V/U Descuento", each if [Cantidad Descuento] <> 0 then [VT Descuento]/[Cantidad Descuento] else 0),

    // ===============================================================
    // 10. LIMPIEZA FINAL Y RENOMBRADO
    // ===============================================================
    Removed_Old_Cols = Table.RemoveColumns(Calc_VU_Desc, {"Cod CBS 1", "Cod CBS 2", "Cod CBS 3", "Cod CBS 4", "Nivel 1", "Nivel 2", "Nivel 3", "Nivel 4"}),

    Renamed_Finals = Table.RenameColumns(Removed_Old_Cols,{
        {"Final_Paquete", "Paquete de Trabajo"}, {"Final_CodAct", "Cod actividad"}, {"Final_CodIns", "Cod ins"},
        {"Final_Razon", "Razon Social"}, {"Final_Titulo", "Titulo"}, {"Final_Proceso", "Tipo"}, {"Final_Reg", "# OC / Contrato"},
        {"New_CBS1", "Cod CBS 1"}, {"New_CBS2", "Cod CBS 2"}, {"New_CBS3", "Cod CBS 3"}, {"New_CBS4", "Cod CBS 4"},
        {"N1", "Nivel 1"}, {"N2", "Nivel 2"}, {"N3", "Nivel 3"}, {"N4", "Nivel 4"}
    }),

    Sorted_Columns = Table.SelectColumns(Renamed_Finals, {
        "Paquete de Trabajo", "Cod CBS 1", "Cod CBS 2", "Cod CBS 3", "Cod CBS 4", "Cod actividad",
        "Nivel 1", "Nivel 2", "Nivel 3", "Nivel 4", "Actividad", "Cod ins", "Ins",
        "Razon Social", "Titulo", "Tipo", "# OC / Contrato",
        "Cantidad PPTO V1", "V/U PPTO V1", "VT PPTO V1", "Cantidad PPTO V2", "V/U PPTO V2", "VT PPTO V2",
        "Cantidad Asegurado", "VT Asegurado", "Cantidad Descuento", "V/U Descuento", "VT Descuento",
        "Cantidad corte", "Valor Recepcion corte"
    }, MissingField.Ignore),
    #"Columnas con nombre cambiado" = Table.RenameColumns(Sorted_Columns,{{"Razon Social", "Nombre contratista"}})

in
    #"Columnas con nombre cambiado"
