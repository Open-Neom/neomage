# Patrones Multi-Agente — Arquitecturas de Coordinacion

## Principio central

Sub-agentes existen para AISLAR CONTEXTO, no para antropomorfizar roles. Cada agente opera en ventana de contexto limpia enfocada en su subtarea.

## Economia de tokens

| Arquitectura | Multiplicador | Caso de uso |
|-------------|---------------|-------------|
| Agente unico chat | 1x | Consultas simples |
| Agente con herramientas | ~4x | Tareas con tools |
| Multi-agente | ~15x | Investigacion/coordinacion compleja |

80% de la varianza en performance se explica por uso de tokens. Mejorar modelo > duplicar tokens.

## 3 patrones dominantes

**Supervisor/Orquestador**: Control centralizado. Descompone objetivos, delega a especialistas, sintetiza.
- Ventaja: Control estricto, human-in-the-loop facil
- Riesgo: Bottleneck del supervisor, cascada de fallos, "juego de telefono" (supervisor parafrasea mal)
- Solucion al telefono: forward_message directo del sub-agente al usuario

**Peer-to-Peer/Swarm**: Sin control central. Agentes comunican via handoff directo.
- Ventaja: Sin punto unico de fallo, exploracion breadth-first
- Riesgo: Divergencia sin state keeper central

**Jerarquico**: Capas de abstraccion (estrategia → planificacion → ejecucion).
- Ventaja: Separacion de concerns clara, diferentes contextos por nivel
- Riesgo: Overhead de coordinacion entre capas

## Mecanismos de aislamiento

- **Delegacion completa**: Compartir contexto entero (maximo capability, derrota el proposito)
- **Paso de instrucciones**: Solo instrucciones necesarias (mantiene aislamiento, limita flexibilidad)
- **Memoria en filesystem**: Estado compartido via storage persistente (evita bloat, introduce latencia)

## Consenso y coordinacion

- Votacion simple es defectuosa (alucinaciones pesan igual que razonamiento solido)
- Votacion ponderada por confianza o expertise
- Protocolos de debate (critica adversarial > consenso colaborativo)
- Triggers de intervencion: stall (sin progreso), sycophancy (imitan sin razonar)

## Modos de fallo

| Fallo | Mitigacion |
|-------|-----------|
| Bottleneck supervisor | Schema de output + checkpointing |
| Overhead coordinacion | Protocolos de handoff minimos, batch resultados |
| Divergencia | Boundaries claros, checks de convergencia, TTL |
| Propagacion de errores | Validar outputs antes de pasar, retry con circuit breakers |
