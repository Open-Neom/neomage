---
name: revision-simplificacion
description: >
  Revisión de código enfocada exclusivamente en detectar sobreingeniería y simplificar.
  Encuentra código redundante: bibliotecas estándar reinventadas, dependencias innecesarias,
  abstracciones especulativas y flexibilidad muerta.
  Produce una línea por hallazgo: ubicación, qué recortar y qué lo reemplaza.
  Se activa al pedir "revisión de sobreingeniería", "qué podemos simplificar", "revisar diff",
  o con el comando /revision-simplificacion.
license: MIT
---

# Revisión de Simplificación de Código

Inspecciona diferencias de código (diffs) buscando complejidad innecesaria. El objetivo principal es que el diff resultante sea lo más corto y simple posible.

## Formato de Hallazgos

`L<línea>: <etiqueta> <qué recortar>. <reemplazo>.`
(o `<archivo>:L<línea>: ...` para revisiones multi-archivo).

Etiquetas:

- `eliminar:` código muerto, flexibilidad no utilizada, características especulativas. Reemplazo: nada.
- `stdlib:` implementación propia de algo que ya ofrece la biblioteca estándar. Nombra la función.
- `nativo:` dependencias o código que hacen lo que la plataforma ya resuelve nativamente. Nombra la característica.
- `yagni:` abstracciones con una sola implementación, configuraciones que nadie cambia, capas con un solo llamador.
- `reducir:` misma lógica en menos líneas de código. Muestra la forma corta.

## Ejemplos

❌ "Esta clase de validación de correo podría ser demasiado compleja, ¿has considerado si todas estas reglas son realmente necesarias?"

✅ `L12-38: stdlib: Clase validadora de 27 líneas. Restringir a comprobar si contiene "@", la validación real ocurre al enviar el correo de confirmación.`

✅ `L4: nativo: Importación de moment.js para una sola llamada de formato. Usar Intl.DateTimeFormat (0 dependencias).`

✅ `repo.py:L88: yagni: Clase AbstractRepository con una sola implementación. Usar la clase concreta directamente hasta que exista una segunda.`

✅ `L52-71: eliminar: Reintentos en llamada local idempotente. Reemplazo: ninguno.`

✅ `L30-44: reducir: Ciclo manual para construir diccionario. Reemplazar por dict(zip(keys, values)) (1 línea).`

## Calificación

Termina con la métrica de reducción estimada:
`neto: -<N> líneas posibles.`

Si no hay nada que recortar:
`Código limpio. Listo para producción.`

## Límites

Ignora problemas de lógica, seguridad o rendimiento convencional (estos corresponden a una revisión de código estándar). Las pruebas de humo mínimas o auto-chequeos basados en `assert` no se consideran sobreingeniería, nunca los marques para eliminar. Esta habilidad solo enumera los hallazgos, no aplica cambios.
"desactivar modo senior" o "modo normal" revierte al estilo de revisión detallado.
