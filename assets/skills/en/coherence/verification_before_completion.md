# Verificacion Antes de Completar

## Ley de hierro

"NINGUNA AFIRMACION DE COMPLETITUD SIN EVIDENCIA FRESCA DE VERIFICACION."

## Proceso

1. Completar la tarea
2. ANTES de reportar exito: ejecutar verificacion independiente
3. Solo reportar exito si la verificacion confirma
4. Si verificacion falla: regresar al paso 1

## Modos de fallo comunes

- "Deberia funcionar" sin verificar (optimismo injustificado)
- Verificar solo happy path (ignorar edge cases)
- Asumir que sin errores = correcto (errores silenciosos)
- Reportar parcialmente completado como completado

## Red flags

- Afirmaciones sin evidencia ("hecho", "funcionando", "corregido")
- Verificacion que solo repite la accion (no verifica resultado)
- Saltarse verificacion por prisa o porque "es obvio"

## Checklist universal

- El resultado coincide con lo solicitado?
- La verificacion es independiente de la implementacion?
- Se probaron los edge cases relevantes?
- Hay evidencia concreta del resultado exitoso?
