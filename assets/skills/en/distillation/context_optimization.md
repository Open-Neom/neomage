# Optimizacion de Contexto — Compactacion, Masking, Cache

## Objetivo

Extender capacidad efectiva de ventanas de contexto limitadas. Optimizacion efectiva puede duplicar o triplicar capacidad sin modelos mas grandes.

## 4 estrategias primarias

**Compactacion**: Resumir contenido al acercarse a limites.
- Prioridad: tool outputs (reemplazar con resumenes) > turnos viejos (resumir conversacion temprana) > docs recuperados (resumir si hay versiones recientes)
- NUNCA comprimir: system prompt
- Tool outputs: preservar hallazgos clave, metricas, conclusiones. Eliminar output verbose.
- Turnos conversacionales: preservar decisiones, compromisos, cambios de contexto. Eliminar relleno.
- Documentos: preservar hechos y claims. Eliminar evidencia y elaboracion.

**Observation Masking**: Tool outputs = 80%+ de tokens en trayectorias de agente.
- Reemplazar outputs verbosos con referencias compactas una vez han servido su proposito
- Nunca maskear: observaciones criticas a tarea actual, turno mas reciente, razonamiento activo
- Considerar: observaciones de 3+ turnos atras, outputs con key points extraibles
- Siempre: outputs repetidos, boilerplate, ya resumidos en conversacion

**KV-Cache Optimization**: Reusar computaciones en requests con prefijos identicos.
- Elementos estables primero (system prompt, tool definitions) → frecuentemente reusados → unicos al final
- Evitar contenido dinamico (timestamps), formatting consistente, estructura estable

**Context Partitioning**: Dividir trabajo en sub-agentes con contextos aislados.
- Cada sub-agente opera en contexto limpio enfocado en su subtarea
- Agregacion: validar completitud, merge compatibles, resumir si excede

## Cuando optimizar

- Utilizacion > 70%
- Calidad degrada en conversaciones largas
- Costos crecientes por contextos largos
- Latencia creciente

## Que aplicar

| Dominante | Estrategia |
|-----------|-----------|
| Tool outputs | Observation masking |
| Docs recuperados | Summarization o partitioning |
| Historial de mensajes | Compactacion con resumen |
| Multiples componentes | Combinar estrategias |

## Targets

- Compactacion: 50-70% reduccion, <5% degradacion calidad
- Masking: 60-80% reduccion en observaciones maskeadas
- Cache: 70%+ hit rate para workloads estables
