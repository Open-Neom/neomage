# Degradacion de Contexto — Patrones de Fallo

## Patrones de degradacion

**Lost-in-Middle**: Curva de atencion en U. Informacion al inicio y final recibe atencion confiable; el medio sufre 10-40% menos recall. Causa: attention sink en primer token + budget limitado.
→ Colocar informacion critica al inicio o final. Headers explicitos para navegacion.

**Context Poisoning**: Errores/alucinaciones entran al contexto y se componen via referencia repetida. Entra por: outputs de herramientas erroneos, documentos recuperados incorrectos, resúmenes intermedios con alucinaciones.
→ Detectar: calidad degradada, herramientas mal usadas, alucinaciones persistentes.
→ Recuperar: truncar al punto pre-envenenamiento, reiniciar con contexto limpio.

**Context Distraction**: Informacion irrelevante compite por atencion limitada. Un solo documento irrelevante reduce performance. El modelo NO puede "saltarse" contexto — atiende a todo.
→ Filtrado de relevancia antes de cargar. Namespacing. Acceso via herramientas en vez de pre-cargar.

**Context Confusion**: Contexto de multiples tareas/fuentes influencia respuestas incorrectamente. Respuestas al aspecto equivocado, herramientas de tarea diferente, mezcla de requisitos.
→ Segmentacion explicita de tareas. Transiciones claras. Aislamiento de estado.

**Context Clash**: Informacion contradictoria de multiples fuentes correctas. Multi-source retrieval, conflictos de version, perspectivas validas pero incompatibles.
→ Marcado explicito de conflictos. Reglas de prioridad. Filtrado de versiones.

## Umbrales empiricos

| Modelo | Inicio degradacion | Degradacion severa |
|--------|-------------------|--------------------|
| GPT-5.2 | ~64K tokens | ~200K tokens |
| Claude Opus 4.5 | ~100K tokens | ~180K tokens |
| Claude Sonnet 4.5 | ~80K tokens | ~150K tokens |
| Gemini 3 Pro | ~500K tokens | ~800K tokens |

## Hallazgos contraintuitivos

- Haystacks desordenados > coherentes (coherencia crea asociaciones falsas)
- Un solo distractor tiene impacto desproporcionado (funcion escalon, no lineal)
- Menor similitud needle-pregunta = degradacion mas rapida con longitud

## Estrategia de 4 cubetas

1. **Write** — Guardar contexto fuera de la ventana (scratchpads, storage externo)
2. **Select** — Jalar contexto relevante via retrieval y filtrado
3. **Compress** — Reducir tokens preservando informacion (resumen, masking)
4. **Isolate** — Dividir contexto entre sub-agentes o sesiones
