---
name: auditoria-complejidad
description: >
  Auditoría de todo el repositorio para detectar sobreingeniería. Realiza una búsqueda en toda la
  base de código para generar una lista priorizada de elementos a eliminar, simplificar o
  reemplazar con equivalentes de la biblioteca estándar o nativos de la plataforma.
  Se activa al solicitar "auditar base de código", "auditar sobreingeniería", "qué puedo eliminar",
  o al usar el comando /auditar-complejidad. Genera un reporte de una sola vez, no aplica cambios.
license: MIT
---

# Auditoría de Complejidad y Sobreingeniería

Escanea todo el repositorio buscando complejidad innecesaria. Clasifica los hallazgos de mayor a menor potencial de reducción de líneas de código.

## Etiquetas de Hallazgos

- `eliminar:` código muerto, flexibilidad no utilizada, características especulativas. Reemplazo: nada.
- `stdlib:` implementación propia de algo que ya ofrece la biblioteca estándar. Nombra la función.
- `nativo:` dependencias o código que hacen lo que la plataforma ya resuelve nativamente. Nombra la característica.
- `yagni:` abstracciones con una sola implementación, configuraciones que nadie cambia, capas con un solo llamador.
- `reducir:` misma lógica en menos líneas de código. Muestra la forma corta.

## Áreas de Inspección

Dependencias innecesarias, interfaces con una sola implementación, fábricas con un solo producto, wrappers que solo delegan llamadas, archivos que exportan una sola cosa, flags de configuración muertos, y algoritmos reinventados.

## Formato de Salida

Una línea por hallazgo, ordenada por impacto:
`<etiqueta> <qué recortar>. <reemplazo>. [ruta/del/archivo]`

Termina con:
`neto: -<N> líneas, -<M> dependencias posibles.`

Si no hay nada que recortar:
`Código limpio. Listo para producción.`

## Límites

Solo evalúa complejidad. Los errores de lógica, fallas de seguridad y problemas de rendimiento corresponden a una revisión convencional, no a esta auditoría. Muestra hallazgos pero no aplica cambios. Es un reporte de una sola ejecución.
"desactivar modo senior" o "modo normal" cancela el modo.
