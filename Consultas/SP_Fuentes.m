let
    Proyecto = Text.Trim(Text.From(ProyectoActual)),
    SiteUrl = "https://colsubsidio365.sharepoint.com/sites/MiGerenciaViv",
    BasePath = "/sites/MiGerenciaViv/Departamento Tecnico/COORDINACION DE PRESUPUESTOS/0. Reportes EDT - Control costos interno/" & Proyecto,
    Headers = [Accept = "application/json;odata=nometadata"],

    FnEncode = (path as nullable text) as nullable text =>
        if path = null then null
        else Text.Combine(List.Transform(Text.Split(path, "/"), each Uri.EscapeDataString(_)), "/"),

    FnReadBinary = (filePath as text) as nullable binary =>
        let
            raw = try Web.Contents(SiteUrl, [
                RelativePath = "/_api/web/GetFileByServerRelativeUrl('" & FnEncode(filePath) & "')/$value",
                Headers = [Accept = "*/*"],
                Timeout = #duration(0, 0, 10, 0),
                ManualStatusHandling = {404, 429, 500, 502, 503, 504}
            ]) otherwise null,
            status = if raw = null then null else try Value.Metadata(raw)[Response.Status] otherwise 200,
            result = if raw = null or status >= 400 then null else Binary.Buffer(raw)
        in
            result,

    FnReadExcel = (filePath as text, fileName as text) as table =>
        let
            binario = FnReadBinary(filePath),
            libro = if binario = null then null else try Excel.Workbook(binario, null, true) otherwise null,
            data = if libro = null or Table.RowCount(libro) = 0 then null else try libro{0}[Data] otherwise null,
            result = if data = null
                then error "No se pudo leer el archivo de SharePoint: " & fileName
                else try Table.PromoteHeaders(data, [PromoteAllScalars = true]) otherwise data
        in
            result,

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
    Sorted = Table.Buffer(Table.Sort(Typed, {{"FileName", Order.Ascending}, {"TimeLastModified", Order.Descending}})),

    PickPath = (fileName as text) as text =>
        let
            candidatos = Table.SelectRows(Sorted, each Text.Upper([FileName]) = Text.Upper(fileName)),
            path = if Table.RowCount(candidatos) = 0
                then error "No se encontro en SharePoint el archivo: " & fileName
                else candidatos{0}[ServerRelativeUrl]
        in
            path,

    Resultado = [
        ASEGURADO = FnReadExcel(PickPath("ASEGURADO.xls"), "ASEGURADO.xls"),
        COMPRAS = FnReadExcel(PickPath("COMPRAS.xls"), "COMPRAS.xls"),
        CONTRATOS = FnReadExcel(PickPath("CONTRATOS.xls"), "CONTRATOS.xls"),
        Archivos = Table.RenameColumns(
            Table.SelectColumns(Sorted, {"Name", "FileName", "ServerRelativeUrl", "TimeLastModified", "Length"}),
            {{"Name", "Centro de Costos"}, {"FileName", "Name"}}
        )
    ]
in
    Resultado
