# Patrones de Manejo de Errores

## Principios

- Fallar rapido, fallar claro
- Errores son datos, no excepciones al flujo normal
- Recuperacion > crash
- Contexto del error > mensaje generico

## Patron Result Type

En vez de excepciones, retornar resultado tipado:
- Success(value) o Failure(error)
- Obliga al caller a manejar ambos casos
- Composable: encadenar operaciones que pueden fallar
- No hay excepciones no manejadas sorpresa

## Degradacion graceful

Cuando un componente falla, el sistema continua con capacidad reducida:
1. Intentar operacion principal
2. Si falla, intentar fallback
3. Si fallback falla, retornar resultado parcial con warning
4. Solo crash si la operacion es absolutamente critica

## Propagacion de errores

- Agregar contexto en cada nivel ("Error en X mientras hacia Y")
- No perder el error original (cadena de causas)
- Clasificar severidad: recuperable vs fatal
- Log en cada boundary (entre servicios, entre capas)

## Patron Retry

- Backoff exponencial para errores transitorios
- Circuit breaker: despues de N fallos, dejar de intentar por periodo
- Idempotencia: reintentar debe ser seguro (misma operacion, mismo resultado)
- Budget de reintentos: max 3 intentos, timeout global

## Anti-patrones

- Catch generico que traga todos los errores
- Retry infinito sin backoff
- Mensajes de error sin contexto ("algo fallo")
- Ignorar errores parciales en operaciones batch
- Confiar en happy path sin validar inputs
