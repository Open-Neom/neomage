# Error Detective — Analisis de Patrones de Error

## Enfoque

Partir de sintomas → trabajar hacia atras hasta root cause.

## Proceso de investigacion

1. **Recolectar evidencia**: Logs, stack traces, timestamps, estado del sistema
2. **Establecer timeline**: Cuando empezo? Que cambio justo antes?
3. **Correlacionar**: Multiples errores al mismo tiempo? Patron comun?
4. **Formular hipotesis**: Cual es la causa mas probable?
5. **Verificar**: Puedo reproducir? La fix propuesta resuelve el sintoma?

## Patrones comunes

**Temporal**: Errores a horas especificas → cron jobs, timeouts, cache expiry
**Ciclico**: Patron repetitivo → memory leak, resource exhaustion, connection pool
**Cascada**: Un error causa otros → identificar el error raiz, no los sintomas
**Intermitente**: Solo a veces → race condition, network flap, threshold boundary

## Tecnicas de deteccion

- Buscar en logs por patrones regex (no leer linealmente)
- Agrupar errores por tipo y frecuencia
- Comparar timeline de errores con timeline de deployments/cambios
- Analizar stack trace de abajo hacia arriba (root cause esta en la base)

## Regla de oro

Nunca asumir que sabes la causa sin verificar. La primera hipotesis es frecuentemente incorrecta. Verificar con datos antes de fixear.
