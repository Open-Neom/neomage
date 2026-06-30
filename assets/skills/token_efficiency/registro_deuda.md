---
name: registro-deuda
description: >
  Recolecta cada comentario de tipo `senior:` en la base de código para construir un registro
  de deuda técnica, asegurando que los atajos y simplificaciones temporales queden documentados.
  Se activa al solicitar "deuda técnica", "registro de deuda", "qué simplificamos", "ledger",
  o "/registro-deuda". Reporte de una sola ejecución, no realiza cambios.
license: MIT
---

# Registro de Deuda Técnica (Comentarios de Simplificación)

Cada atajo deliberado se marca en el código con un comentario `senior:` que describe su límite (techo) y la ruta de actualización. Esta habilidad los consolida en un reporte unificado para evitar que las simplificaciones temporales se vuelvan permanentes de forma silenciosa.

## Escaneo

Inspecciona el repositorio buscando comentarios que comiencen con `senior:`, omitiendo directorios de dependencias (`node_modules`, `.git`) y salidas de construcción:

`grep -rnE '(#|//) ?senior:' .`

Cada coincidencia representa una fila en el reporte.

## Formato de Salida

Una fila por marcador, agrupada por archivo:

`<archivo>:<línea> — <qué se simplificó>. límite: <techo nombrado>. actualización: <el disparador para cambiarlo>.`

La convención en el código es:
`senior: <límite>, <disparador de actualización>`

## Alertas de Riesgo

Cualquier comentario `senior:` que no especifique una ruta de actualización o disparador claro se marcará con la etiqueta `[sin-disparador]`. Estas simplificaciones corren el riesgo de quedar permanentes sin control.

Termina con:
`<N> marcadores encontrados, <M> sin disparador.`

Si no hay comentarios:
`Sin deuda técnica registrada. Ledger limpio.`

## Límites

Genera un reporte exclusivamente de lectura. Si el usuario lo solicita, guarda el reporte en un archivo (ej. `DEUDA-TECNICA.md`). Es un reporte de una sola ejecución.
