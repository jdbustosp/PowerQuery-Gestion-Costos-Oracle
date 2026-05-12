# PowerQuery Gestion Costos Oracle

Repositorio de consultas Power Query para gestion de costos.

## Consultas incluidas

- `ProyectoActual`
- `ConfigProyecto`
- `F_Globales`
- `SP_Archivos_Proyecto`
- `SP_ASEGURADO`
- `SP_COMPRAS`
- `SP_CONTRATOS`
- `PRESUPUESTO`
- `ASEGURADO`
- `COMPARATIVOS`
- `DISPONIBLE`
- `ORACLE`
- `BD`

Pendientes por agregar cuando este disponible el codigo:

- `PROVISIONES`
- `LIQUIDACION`

## Estructura

Las consultas estan guardadas como archivos `.m` en la carpeta `Consultas/`.

## Configuracion por proyecto

La consulta `ProyectoActual` define que configuracion usar. Valores configurados:

- `MONGUI`: jerarquia larga, 5 niveles CBS.
- `PAMPLONA 1`: jerarquia larga, 5 niveles CBS.
- `VERSALLES`: jerarquia corta, 3 niveles CBS.

`ConfigProyecto` centraliza la configuracion. `PRESUPUESTO` siempre entrega una salida normalizada con las columnas `Cod CBS 1` a `Cod CBS 4` y `Nivel 1` a `Nivel 4`; cuando el proyecto usa jerarquia corta, los niveles que no aplican quedan en `null`.

## Origen SharePoint

Las fuentes externas `ASEGURADO`, `COMPRAS` y `CONTRATOS` se leen desde SharePoint con la ruta:

`/Departamento Tecnico/COORDINACION DE PRESUPUESTOS/0. Reportes EDT - Control costos interno/<ProyectoActual>/<Centro de Costos>/Actual`

Los archivos esperados son:

- `ASEGURADO.xls`
- `COMPRAS.xls`
- `CONTRATOS.xls`
