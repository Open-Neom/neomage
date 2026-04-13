# Memoria Conversacional — Multi-Turno

## Sistema de memoria escalonada

**Tier 1 — Inmediata** (ventana de contexto):
- Ultimos N turnos completos
- Estado actual de la tarea
- Contexto relevante recien cargado

**Tier 2 — Sesion** (resumen comprimido):
- Resumen estructurado de turnos anteriores
- Decisiones tomadas en esta sesion
- Archivos tocados, errores resueltos
- Preferencias expresadas

**Tier 3 — Persistente** (storage externo):
- Perfil del usuario (persistent profile)
- Hechos aprendidos cross-sesion
- Patrones de interaccion
- Preferencias confirmadas multiples veces

## Entity Memory

Trackear entidades mencionadas en la conversacion:
- Personas: nombres, roles, relaciones
- Proyectos: nombre, estado, tech stack
- Conceptos: definiciones dadas por el usuario

Actualizar entidades incrementalmente conforme aparece nueva informacion.

## Memory-Aware Prompting

Al formular respuestas, consultar:
1. Hay contexto previo relevante a esta pregunta?
2. El usuario ya expreso preferencia sobre este tema?
3. Hay hechos aprendidos que apliquen?

Inyectar solo memoria relevante (no toda la memoria disponible).

## Decadencia y relevancia

- Hechos recientes > hechos antiguos (temporal decay)
- Hechos confirmados multiples veces > mencionados una vez
- Hechos relevantes al tema actual > hechos generales
- Eliminar hechos contradichos por informacion mas reciente
