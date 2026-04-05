# Prompt Caching — Consolidacion de Contexto Frecuente

## Concepto

Reusar contexto computado en requests con prefijos identicos. Evitar recomputar lo mismo repetidamente.

## Estrategias

**Anthropic Prompt Caching**: Cache de KV-blocks para prefijos estables.
- Colocar contenido estable al inicio del prompt
- System prompt + tool definitions = altamente cacheable
- Contenido dinamico al final
- Reduccion de costo: hasta 90% en prefijo cacheado

**Response Caching**: Cachear respuestas completas para queries identicas o similares.
- Key: hash del prompt completo (o embedding similarity)
- TTL basado en volatilidad del contenido
- Invalidar al cambiar datos subyacentes

**Cache Augmented Generation (CAG)**: Pre-cargar conocimiento en cache y consultar en vez de hacer RAG.
- Para datasets estables y bien definidos
- Elimina latencia de retrieval
- Trade-off: menos flexible que RAG para contenido dinamico

## Patrones de invalidacion

- Time-based: TTL fijo por tipo de contenido
- Event-based: invalidar al detectar cambio en datos fuente
- Version-based: nuevo hash de contenido = nuevo cache entry

## Anti-patrones

- Cachear contenido altamente dinamico (timestamps, datos en vivo)
- Cache sin estrategia de invalidacion (datos stale)
- Ignorar cache-friendliness en diseno de prompts
- Cache demasiado granular (overhead > beneficio)

## Aplicacion en Neomage

- System prompt + personalidad + herramientas = cacheable (cambia raramente)
- User profile summary = cacheable per session
- Historial de conversacion = NO cacheable (cambia cada turno)
- Resultados de web search = cache corto (TTL minutos)
