# Optimizacion Web

- Core Web Vitals son el estandar: LCP (carga), FID/INP (interactividad), CLS (estabilidad visual)
- LCP < 2.5s: optimizar imagen hero, preload fuentes criticas, server-side rendering para contenido above-the-fold
- INP < 200ms: dividir long tasks, usar requestIdleCallback, debounce inputs, evitar layout thrashing
- CLS < 0.1: dimensiones explicitas en imagenes/videos, reservar espacio para contenido dinamico

## Estrategias por capa
- **Red**: HTTP/2+, compresion Brotli, CDN global, preconnect a origenes criticos, cache headers agresivos
- **JavaScript**: code splitting por ruta, tree shaking, dynamic imports, defer scripts no criticos
- **CSS**: critical CSS inline, cargar resto async, purgar clases no usadas
- **Imagenes**: formatos modernos (WebP/AVIF), responsive srcset, lazy loading nativo, CDN de imagenes
- **Fuentes**: font-display: swap, preload fuentes criticas, subset solo caracteres necesarios

## Caching multinivel
- Browser cache: Cache-Control con max-age largo para assets con hash
- Service Worker: cache first para assets, network first para API
- CDN: cache en edge, invalidacion por tag/path
- Server: cache de queries costosas, invalidar por evento

## Anti-patrones
- Cargar fuentes de terceros sin preconnect
- Imagenes sin dimensiones explicitas (causa CLS)
- JavaScript sincrono en el head
- No medir despues de cada cambio
