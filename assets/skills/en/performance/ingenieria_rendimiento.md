# Ingenieria de Rendimiento

- El rendimiento es una caracteristica del producto; no optimizar prematuramente, pero medir desde el dia uno
- Presupuesto de rendimiento: establecer limites medibles (LCP < 2.5s, FID < 100ms, CLS < 0.1) antes de desarrollar
- Medir en condiciones reales: dispositivos promedio del usuario, red tipica, datos representativos
- Las metricas sinteticas (Lighthouse) son utiles para CI; las metricas de campo (RUM) reflejan la experiencia real
- El cuello de botella nunca esta donde crees: siempre perfilar antes de optimizar

## Metodologia de optimizacion
1. Medir: establecer baseline con metricas objetivas
2. Identificar: encontrar el cuello de botella real (profiling, tracing)
3. Optimizar: cambiar UNA cosa a la vez
4. Verificar: medir de nuevo para confirmar mejora
5. Repetir: hasta alcanzar el presupuesto

## Areas criticas
- Red: minimizar requests, comprimir, cachear agresivamente, lazy load
- CPU: evitar long tasks (>50ms), usar web workers para computo pesado
- Memoria: prevenir leaks, liberar referencias, usar pools para objetos frecuentes
- Renderizado: minimizar reflows/repaints, usar will-change con moderacion
- Bundle: code splitting, tree shaking, importaciones dinamicas

## Anti-patrones
- Optimizar sin medir primero (optimizacion prematura)
- Medir solo en hardware de desarrollo de alta gama
- Cachear sin estrategia de invalidacion
- Cargar todo al inicio en vez de lazy loading
