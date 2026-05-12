let
    ParamProyecto = Text.Trim(Text.From(ProyectoActual)),
    SiteUrl = "https://colsubsidio365.sharepoint.com/sites/MiGerenciaViv",
    BasePath = "/sites/MiGerenciaViv/Departamento Tecnico/COORDINACION DE PRESUPUESTOS/0. Reportes EDT - Control costos interno/" & ParamProyecto,
    Headers = [Accept="application/json;odata=nometadata"],
    FnEncode = F_Globales[FnEncode],

    FolderResponse = try Json.Document(Web.Contents(SiteUrl, [
        RelativePath = "/_api/web/GetFolderByServerRelativeUrl('" & FnEncode(BasePath) & "')/Folders",
        Query = [#"$select" = "Name"],
        Headers = Headers,
        Timeout = #duration(0, 0, 5, 0)
    ])) otherwise null,

    CCFolders =
        if FolderResponse = null or not Record.HasFields(FolderResponse, "value")
        then #table({"Name"}, {})
        else Table.FromRecords(FolderResponse[value]),

    WithFiles = Table.AddColumn(CCFolders, "Archivos", each
        let
            ccActualPath = BasePath & "/" & [Name] & "/Actual",
            result = try Json.Document(Web.Contents(SiteUrl, [
                RelativePath = "/_api/web/GetFolderByServerRelativeUrl('" & FnEncode(ccActualPath) & "')/Files",
                Query = [#"$select" = "Name,ServerRelativeUrl,TimeLastModified,Length"],
                Headers = Headers,
                Timeout = #duration(0, 0, 5, 0)
            ])) otherwise null
        in
            if result <> null and Record.HasFields(result, "value") then Table.FromRecords(result[value]) else null
    ),

    ValidCCs = Table.SelectRows(WithFiles, each [Archivos] <> null),
    Expanded = Table.ExpandTableColumn(
        ValidCCs,
        "Archivos",
        {"Name", "ServerRelativeUrl", "TimeLastModified", "Length"},
        {"FileName", "ServerRelativeUrl", "TimeLastModified", "Length"}
    ),

    Relevant = Table.SelectRows(Expanded, each
        not Text.StartsWith([FileName], "~$") and List.Contains(
            {"ASEGURADO.XLS", "COMPRAS.XLS", "CONTRATOS.XLS"},
            Text.Upper([FileName])
        )
    ),

    Typed = Table.TransformColumnTypes(Relevant, {{"TimeLastModified", type datetimezone}, {"Length", Int64.Type}}, "en-US"),
    Sorted = Table.Sort(Typed, {{"Name", Order.Ascending}, {"FileName", Order.Ascending}, {"TimeLastModified", Order.Descending}}),
    Final = Table.Buffer(Table.RenameColumns(
        Table.SelectColumns(Sorted, {"Name", "FileName", "ServerRelativeUrl", "TimeLastModified", "Length"}),
        {{"Name", "Centro de Costos"}, {"FileName", "Name"}}
    ))
in
    Final
