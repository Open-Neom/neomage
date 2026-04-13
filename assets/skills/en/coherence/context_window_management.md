# Gestion de Ventana de Contexto

## Estrategia escalonada

**Tier 1 — Core (siempre presente)**: System prompt, identidad, restricciones criticas. ~5-10% del budget.

**Tier 2 — Tarea activa (dinamico)**: Instrucciones de tarea, datos relevantes, herramientas activas. ~40-50%.

**Tier 3 — Historial (comprimido)**: Resumen de conversacion, decisiones previas. ~20-30%.

**Tier 4 — Buffer (reserva)**: Espacio para respuesta del modelo y tool outputs inesperados. ~15-20%.

## Optimizacion de posicion serial

Informacion critica en posiciones de alta atencion:
- **Inicio**: Identidad, objetivo principal, restricciones duras
- **Final**: Tarea inmediata, datos mas recientes, instruccion de accion
- **Medio**: Contexto de soporte, historial, evidencia complementaria

## Summarization inteligente

Triggers:
- Utilizacion > 75%: comprimir tier 3 (historial)
- Utilizacion > 85%: comprimir tier 2 no-esencial
- Utilizacion > 95%: emergencia — solo tier 1 + tarea inmediata

Nunca comprimir: system prompt, tarea activa, datos sin procesar del turno actual.

## Anti-patrones

- **Truncamiento naive**: Cortar por tamano pierde informacion critica al azar
- **Ignorar costos de tokens**: Cada token cuenta, especialmente en produccion
- **One-size-fits-all**: Diferentes tareas requieren diferente distribucion del budget
