# Patrones de Localizacion

- Locale = idioma + region: es-MX (espanol Mexico) vs es-ES (espanol Espana); diferencias reales en vocabulario y formato
- Fallback chain: es-MX → es → en (idioma especifico → idioma base → idioma por defecto)
- Lazy loading de traducciones: cargar solo el locale activo, no todos; reducir bundle size
- Namespace por modulo: `auth.login.title`, `dashboard.metrics.revenue`; evita colisiones y facilita ownership

## Consideraciones culturales
- Colores tienen significados diferentes: rojo = peligro (occidente) vs prosperidad (China)
- Iconos y gestos no son universales: pulgar arriba es ofensivo en algunas culturas
- Formatos de nombre: nombre-apellido (occidente) vs apellido-nombre (Asia oriental)
- Direcciones postales varian drasticamente entre paises

## Moneda y numeros
- Siempre almacenar montos en centavos/unidad minima como entero (evitar floating point)
- Mostrar simbolo de moneda segun locale: $1,234.00 (en-US) vs 1.234,00 $ (es-MX)
- Zonas horarias: almacenar en UTC, mostrar en timezone del usuario; nunca asumir timezone

## Testing de localizacion
- Pseudo-localizacion: reemplazar caracteres con acentuados para detectar hardcoded strings
- Test con texto largo (aleman) y corto (chino) para verificar layouts
- Verificar RTL con contenido real, no solo mirroring mecanico

## Anti-patrones
- Strings en codigo fuente, fechas formateadas manualmente, ignorar zonas horarias
