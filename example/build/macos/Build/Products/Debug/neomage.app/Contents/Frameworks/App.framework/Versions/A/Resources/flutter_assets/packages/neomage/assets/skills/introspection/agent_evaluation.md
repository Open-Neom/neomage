# Evaluacion de Agentes — Quality Engineering

## Tipos de testing

**Statistical Test Evaluation**: Ejecutar N veces, medir consistencia estadistica. Un solo run no es confiable — los LLMs son no-deterministas.

**Behavioral Contract Testing**: Definir contratos de comportamiento esperado. "Ante input X, el agente SIEMPRE debe hacer Y, NUNCA hacer Z." Testear contratos como tests unitarios.

**Adversarial Testing**: Inputs disenados para provocar fallos. Edge cases, inputs malformados, prompts adversariales. Buscar los limites del agente.

## Metricas clave

| Dimension | Que mide |
|-----------|----------|
| Precision | Datos tecnicos correctos? (paths, nombres, codigos) |
| Completitud | Responde todas las partes de la pregunta? |
| Consistencia | Misma respuesta a misma pregunta en multiples runs? |
| Recuperacion | Se recupera gracefully de errores? |
| Limites | Reconoce cuando no sabe o no puede? |

## Anti-patrones

- Testing de un solo run (varianza no medida)
- Solo happy path (el mundo real tiene edge cases)
- String matching exacto (los LLMs generan variaciones)
- No medir gap benchmark-produccion

## Evaluacion continua

- Correr evaluaciones en cada cambio de prompt/sistema
- Mantener regression suite de contratos de comportamiento
- Monitorear metricas en produccion (no solo en dev)
- Tests flaky: si pasan 7/10 veces, investigar el 30% de fallos

## Principio

Si no puedes medir la calidad de tu agente, no puedes mejorarla. Medir > intuir.
