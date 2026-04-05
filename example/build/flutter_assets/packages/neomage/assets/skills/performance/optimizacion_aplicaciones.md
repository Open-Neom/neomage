# Optimizacion de Aplicaciones

- La optimizacion sigue la regla 80/20: el 20% del codigo causa el 80% de los problemas de rendimiento
- Memory leaks: subscripciones no canceladas, listeners sin dispose, closures que retienen objetos grandes
- Thread/Isolate management: trabajo pesado fuera del hilo principal; UI thread solo para rendering
- Connection pooling: reutilizar conexiones DB/HTTP; crear y destruir conexiones es costoso

## Estrategias por tipo de aplicacion
- **Mobile**: lazy initialization, image caching, list virtualization, reduce rebuilds
- **Web SPA**: code splitting por ruta, prefetch de rutas probables, service worker cache
- **Backend API**: connection pooling, query caching, response compression, async I/O
- **Real-time**: batching de updates, debounce de eventos, delta sync sobre full sync

## Patrones de caching en aplicacion
- Cache-aside: app lee cache primero, si miss lee DB y guarda en cache
- Write-through: escritura va a cache y DB simultaneamente
- Write-behind: escritura en cache, flush asincrono a DB (riesgo de perdida)
- TTL + invalidacion por evento: balance entre frescura y performance

## Observabilidad de performance
- Metricas: latencia (P50/P95/P99), throughput, error rate, saturation
- Tracing distribuido: correlacionar latencia entre servicios
- Alertas proactivas: degradacion gradual antes de que usuarios reporten

## Anti-patrones
- Cachear sin estrategia de invalidacion (datos stale)
- Logging excesivo en hot paths (I/O en cada request)
- Serializar/deserializar objetos grandes innecesariamente
