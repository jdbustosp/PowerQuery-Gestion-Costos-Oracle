let
    ProyectoParam = Text.Upper(Text.Trim(Text.From(ProyectoActual))),
    Configs = #table(
        type table [
            Proyecto = text,
            TipoJerarquia = text,
            NivelesCBS = Int64.Type,
            VersionPresupuestoDisponible = text
        ],
        {
            {"MONGUI", "LARGA", 5, "V1"},
            {"PAMPLONA 1", "LARGA", 5, "V1"},
            {"VERSALLES", "CORTA", 3, "V2"}
        }
    ),
    Match = Table.SelectRows(Configs, each [Proyecto] = ProyectoParam),
    Config = if Table.RowCount(Match) = 0
        then error "Proyecto no configurado en ConfigProyecto: " & ProyectoParam
        else Match{0}
in
    Config
