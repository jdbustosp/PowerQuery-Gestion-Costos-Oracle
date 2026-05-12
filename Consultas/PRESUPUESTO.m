let
    // 1. CARGAR DATOS
    Origen = Excel.CurrentWorkbook(){[Name="PRESUPUESTO"]}[Content],

    // 2. LIMPIEZA Y TIPOS (Convertimos Cod CBS a texto para analizarlo)
    TipoCambiado = Table.TransformColumnTypes(Origen,{
        {"Cod CBS", type text},
        {"Descripción", type text},
        {"UM", type text},
        {"Cant", type number},
        {"VrUni", type number},
        {"Total", type number}
    }),

    // -----------------------------------------------------------------------
    // 3. CAPTURAR PAQUETE DE TRABAJO (CORREGIDO)
    // -----------------------------------------------------------------------
    // Lógica: Si Cod CBS no tiene guion "-" (ej: "2582"), tomamos la [Descripción]
    Add_Paquete = Table.AddColumn(TipoCambiado, "Paquete_Temp", each
        if [Cod CBS] <> null
           and [Cod CBS] <> "Gran Total"
           and not Text.Contains([Cod CBS], "-")
        then [Descripción]  // <--- AQUÍ ESTABA LA CLAVE: Tomar la Descripción ("PRELIMINARES")
        else null
    ),

    // Rellenamos hacia abajo
    Fill_Paquete = Table.FillDown(Add_Paquete,{"Paquete_Temp"}),

    // Renombramos a la oficial
    Rename_Paquete = Table.RenameColumns(Fill_Paquete,{{"Paquete_Temp", "Paquete de Trabajo"}}),

    // -----------------------------------------------------------------------
    // 4. CALCULAR NIVELES (Jerarquía 6)
    // -----------------------------------------------------------------------
    AgregarNivel = Table.AddColumn(Rename_Paquete, "NivelCalculado", each
        if [Cod CBS] = null then null
        else if not Text.Contains([Cod CBS], "-") then 0 // Nivel 0 = Encabezado
        else if Text.Length([Cod CBS]) < 15 then 6       // Nivel 6 = Insumo
        else if Text.EndsWith([Cod CBS], "-00-00-00-0000-000") then 1
        else if Text.EndsWith([Cod CBS], "-00-00-0000-000") then 2
        else if Text.EndsWith([Cod CBS], "-00-0000-000") then 3
        else if Text.EndsWith([Cod CBS], "-0000-000") then 4
        else 5
    ),

    // 5. CREAR COLUMNAS JERARQUÍA
    Col_C1 = Table.AddColumn(AgregarNivel, "C1", each if [NivelCalculado]=1 then [Cod CBS] else null),
    Col_D1 = Table.AddColumn(Col_C1,       "D1", each if [NivelCalculado]=1 then [Descripción] else null),

    Col_C2 = Table.AddColumn(Col_D1,       "C2", each if [NivelCalculado]=2 then [Cod CBS] else null),
    Col_D2 = Table.AddColumn(Col_C2,       "D2", each if [NivelCalculado]=2 then [Descripción] else null),

    Col_C3 = Table.AddColumn(Col_D2,       "C3", each if [NivelCalculado]=3 then [Cod CBS] else null),
    Col_D3 = Table.AddColumn(Col_C3,       "D3", each if [NivelCalculado]=3 then [Descripción] else null),

    Col_C4 = Table.AddColumn(Col_D3,       "C4", each if [NivelCalculado]=4 then [Cod CBS] else null),
    Col_D4 = Table.AddColumn(Col_C4,       "D4", each if [NivelCalculado]=4 then [Descripción] else null),

    Col_C5 = Table.AddColumn(Col_D4,       "C5", each if [NivelCalculado]=5 then [Cod CBS] else null),
    Col_D5 = Table.AddColumn(Col_C5,       "D5", each if [NivelCalculado]=5 then [Descripción] else null),
    Col_UM5= Table.AddColumn(Col_D5,       "UM5",each if [NivelCalculado]=5 then [UM] else null),

    // 6. RELLENAR TODO
    RellenarTodo = Table.FillDown(Col_UM5, {"C1","D1", "C2","D2", "C3","D3", "C4","D4", "C5","D5","UM5"}),

    // 7. FILTRAR (Solo Insumos)
    // Esto borra las filas de encabezado (2582, etc.) pero deja el dato en la columna Paquete
    FiltrarInsumos = Table.SelectRows(RellenarTodo, each ([NivelCalculado] = 6) and ([Cod CBS] <> null) and ([Cod CBS] <> "Gran Total")),

    // 8. AGRUPAR
    Agrupar = Table.Group(FiltrarInsumos,
        {"Paquete de Trabajo", "C1", "D1", "C2", "D2", "C3", "D3", "C4", "D4", "C5", "D5", "UM5", "Cod CBS", "Descripción", "UM"},
        {{"Cant", each List.Sum([Cant]), type number}, {"Total", each List.Sum([Total]), type number}}
    ),

    // 9. COLUMNAS FINALES
    Nivel1 = Table.AddColumn(Agrupar, "Nivel 1", each [C1] & " - " & [D1]),
    Nivel2 = Table.AddColumn(Nivel1,  "Nivel 2", each [C2] & " - " & [D2]),
    Nivel3 = Table.AddColumn(Nivel2,  "Nivel 3", each [C3] & " - " & [D3]),
    Nivel4 = Table.AddColumn(Nivel3,  "Nivel 4", each [C4] & " - " & [D4]),
    Activ  = Table.AddColumn(Nivel4,  "Actividad", each [C5] & " - " & [D5] & " (" & (if [UM5]=null then "" else [UM5]) & ")"),
    Insumo = Table.AddColumn(Activ,   "Ins", each [Descripción] & " (" & [UM] & ")"),

    CalcVrUni = Table.AddColumn(Insumo, "VrUni", each if [Cant] <> 0 then [Total] / [Cant] else 0, type number),

    AddTipo = Table.AddColumn(CalcVrUni, "Tipo", each "PRESUPUESTO V1", type text),

    Renombrar = Table.RenameColumns(AddTipo,{
        {"C1", "Cod CBS 1"},
        {"C2", "Cod CBS 2"},
        {"C3", "Cod CBS 3"},
        {"C4", "Cod CBS 4"},
        {"C5", "Cod actividad"},
        {"Cod CBS", "Cod ins"},
        {"Cant", "Cantidad PPTO V2"},
        {"VrUni", "V/U PPTO V2"},
        {"Total", "VT PPTO V2"}
    }),

    Orden = Table.SelectColumns(Renombrar, {
        "Paquete de Trabajo",
        "Cod CBS 1", "Cod CBS 2", "Cod CBS 3", "Cod CBS 4", "Cod actividad", "Cod ins",
        "Nivel 1", "Nivel 2", "Nivel 3", "Nivel 4", "Actividad", "Ins", "UM",
        "Tipo", "Cantidad PPTO V2", "V/U PPTO V2", "VT PPTO V2"
    }),
    #"Columnas quitadas" = Table.RemoveColumns(Orden,{"UM"}),
    #"Columnas con nombre cambiado" = Table.RenameColumns(#"Columnas quitadas",{{"Cantidad PPTO V2", "Cantidad PPTO V1"}, {"V/U PPTO V2", "V/U PPTO V1"}, {"VT PPTO V2", "VT PPTO V1"}})
in
    #"Columnas con nombre cambiado"
