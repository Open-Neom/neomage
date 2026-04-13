# Perfilado de Rendimiento

- Perfilar antes de optimizar: las suposiciones sobre cuellos de botella estan equivocadas el 80% del tiempo
- Tipos de profiling: CPU (flame charts), memoria (heap snapshots), red (waterfall), rendering (paint profiler)
- Flame charts: el ancho es tiempo de ejecucion; las funciones mas anchas en la base son las mas costosas
- Heap snapshots: comparar dos snapshots para encontrar leaks; objetos que crecen entre capturas son sospechosos

## Herramientas por plataforma
- Web: Chrome DevTools (Performance tab, Memory tab, Lighthouse), WebPageTest
- Flutter: DevTools (Timeline, Memory, CPU Profiler), Observatory
- Backend: pprof (Go), py-spy (Python), async-profiler (JVM), perf (Linux)
- Base de datos: EXPLAIN ANALYZE, slow query log, pg_stat_statements

## Metodologia de profiling
1. Reproducir el escenario problematico de forma consistente
2. Capturar profile con datos representativos (no datos de prueba minimos)
3. Identificar el hot path (camino critico que consume mas tiempo)
4. Optimizar el hot path especificamente
5. Verificar que la optimizacion no introduce regresiones en otros paths

## Metricas clave
- P50 (mediana): experiencia tipica
- P95/P99: experiencia de cola (usuarios mas afectados)
- Throughput: operaciones por segundo
- Memory watermark: pico de uso de memoria

## Anti-patrones
- Promediar tiempos en vez de ver percentiles (oculta cola)
- Perfilar en modo debug (overhead distorsiona resultados)
- Optimizar funciones que representan <5% del tiempo total
