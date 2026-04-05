# Optimizacion SQL

- Toda query lenta se diagnostica con EXPLAIN ANALYZE; nunca optimizar sin ver el plan de ejecucion
- Indices: la herramienta mas poderosa; cubrir columnas de WHERE, JOIN, ORDER BY
- Indices compuestos: el orden importa; columna mas selectiva primero, igualdad antes que rango
- Covering index: incluir columnas del SELECT para evitar acceso a tabla (index-only scan)

## Patrones de optimizacion
- **N+1**: detectar con count de queries; resolver con JOIN o subquery batch
- **Paginacion**: keyset pagination (WHERE id > last_id) escala mejor que OFFSET para datasets grandes
- **Agregaciones**: materializar vistas para reportes frecuentes; actualizar con triggers o cron
- **Bulk operations**: INSERT ... VALUES multiples, COPY para cargas masivas, batch UPDATE con CTE
- **Particionado**: tablas grandes por fecha, region o rango; mejora queries que filtran por partition key

## Indices especializados
- B-tree: default, optimo para igualdad y rango
- GIN: full-text search, JSONB, arrays
- GiST: geometria, rangos, proximidad
- BRIN: datos naturalmente ordenados (timestamps)
- Parciales: indexar solo subconjunto (WHERE active = true)

## Monitoreo
- Slow query log con umbral progresivo (1s → 500ms → 100ms)
- pg_stat_statements para top queries por tiempo total
- Alertas en P99 de latencia por endpoint

## Anti-patrones
- SELECT * cuando solo necesitas 2 columnas
- Indices en columnas de baja cardinalidad (boolean)
- Funciones en WHERE que invalidan uso de indices
- Falta de LIMIT en queries exploratorias
