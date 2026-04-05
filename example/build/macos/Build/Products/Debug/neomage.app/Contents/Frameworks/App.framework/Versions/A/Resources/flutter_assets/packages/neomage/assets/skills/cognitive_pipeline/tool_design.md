# Diseno de Herramientas para Agentes

## Principio central

Tool description = prompt. La descripcion de la herramienta ES la instruccion que el agente usa para decidir cuando y como usarla. Descripciones pobres = agente adivinando.

## Principio de consolidacion

Si un humano no puede decidir definitivamente que herramienta usar en una situacion, un agente tampoco. Reducir ambiguedad entre herramientas.

## Reduccion arquitectonica

Menos herramientas con capacidades claras > muchas herramientas con overlap.
- 3-5 herramientas bien disenadas > 15 herramientas similares
- Cada herramienta tiene dominio claro y no-ambiguo
- Nombres descriptivos que indican accion

## Descripcion efectiva

Incluir en la descripcion:
- QUE hace (accion concreta)
- CUANDO usarla (triggers claros)
- CUANDO NO usarla (boundaries)
- Formato de output esperado
- Ejemplos de uso si la logica es compleja

## Formato de respuesta

- Retornar datos estructurados cuando sea posible
- Incluir metadata util (timestamps, confidence, source)
- Errores informativos con contexto y sugerencia de recovery
- Tamano de output controlado (resumir si es verbose)

## Anti-patrones

- Herramientas con nombres genericos ("process", "handle", "do")
- Overlap entre herramientas sin criterio de seleccion claro
- Output sin estructura (texto libre cuando podria ser JSON)
- Herramientas que hacen demasiadas cosas (split responsabilidades)
- Descripciones vagas que dejan al agente adivinando
