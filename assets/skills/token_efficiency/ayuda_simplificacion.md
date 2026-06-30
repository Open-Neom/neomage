---
name: ayuda-simplificacion
description: >
  Ficha de referencia rápida para los modos, comandos y habilidades de simplificación.
  Muestra la información de una sola vez. Se activa con "ayuda modo senior",
  "ayuda simplificación", o /ayuda-simplificacion.
license: MIT
---

# Ayuda de Modo Senior (Simplificación)

Muestra esta tarjeta de referencia rápida. Es de una sola visualización; no altera estados ni persiste archivos.

## Niveles

| Nivel | Comando | Comportamiento |
|-------|---------|----------------|
| **Leve** | `/senior leve` | Construye lo solicitado, pero sugiere la alternativa más simple en una línea. |
| **Total** | `/senior` | Aplica la escalera YAGNI (biblioteca estándar, nativo, una línea). Por defecto. |
| **Ultra** | `/senior ultra` | Extremista de YAGNI. Eliminación antes que adición. Cuestiona requisitos. |

El nivel persiste hasta que se cambie o finalice la sesión.

## Habilidades Disponibles

| Habilidad | Comando | Propósito |
|-----------|---------|-----------|
| **desarrollador-senior** | `/senior` | Modo de simplificación activo para cada respuesta. |
| **revision-simplificacion** | `/revision-simplificacion` | Revisa diffs buscando sobreingeniería. |
| **registro-deuda** | `/registro-deuda` | Lista comentarios `senior:` en el repositorio. |
| **auditoria-complejidad** | `/auditoria-complejidad` | Auditoría de todo el repositorio para simplificación. |
| **ayuda-simplificacion** | `/ayuda-simplificacion` | Muestra esta tarjeta de ayuda. |

## Desactivación

Di "desactivar modo senior" o "modo normal" para volver al comportamiento estándar. También funciona `/senior off`.
