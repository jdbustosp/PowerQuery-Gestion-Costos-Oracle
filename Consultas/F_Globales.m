let
    FnEncode = (path as nullable text) as nullable text =>
        if path = null then null
        else Text.Combine(List.Transform(Text.Split(path, "/"), each Uri.EscapeDataString(_)), "/"),

    FnReadSPBinary = (siteUrl as text, filePath as text) as nullable binary =>
        let
            raw = try Web.Contents(siteUrl, [
                RelativePath = "/_api/web/GetFileByServerRelativeUrl('" & FnEncode(filePath) & "')/$value",
                Headers = [Accept = "*/*"],
                Timeout = #duration(0, 0, 10, 0),
                ManualStatusHandling = {404, 429, 500, 502, 503, 504}
            ]) otherwise null,
            status = if raw = null then null else try Value.Metadata(raw)[Response.Status] otherwise 200,
            result = if raw = null or status >= 400 then null else Binary.Buffer(raw)
        in
            result,

    FnReadSPExcel = (siteUrl as text, filePath as text) as nullable table =>
        let
            binario = FnReadSPBinary(siteUrl, filePath),
            libro = if binario = null then null else try Excel.Workbook(binario, null, true) otherwise null,
            data = if libro = null or Table.RowCount(libro) = 0 then null else try libro{0}[Data] otherwise null,
            result = if data = null then null else try Table.PromoteHeaders(data, [PromoteAllScalars = true]) otherwise data
        in
            result,

    FnPickLatestSPExcel = (archivos as table, fileName as text) as table =>
        let
            candidatos = Table.Sort(
                Table.SelectRows(archivos, each Text.Upper([Name]) = Text.Upper(fileName)),
                {{"TimeLastModified", Order.Descending}, {"Name", Order.Ascending}}
            ),
            path = if Table.RowCount(candidatos) = 0 then error "No se encontro en SharePoint el archivo: " & fileName else candidatos{0}[ServerRelativeUrl],
            tabla = FnReadSPExcel("https://colsubsidio365.sharepoint.com/sites/MiGerenciaViv", path),
            result = if tabla = null then error "No se pudo leer el archivo de SharePoint: " & fileName else tabla
        in
            result,

    Funciones = [
        FnEncode = FnEncode,
        FnReadSPBinary = FnReadSPBinary,
        FnReadSPExcel = FnReadSPExcel,
        FnPickLatestSPExcel = FnPickLatestSPExcel
    ]
in
    Funciones
