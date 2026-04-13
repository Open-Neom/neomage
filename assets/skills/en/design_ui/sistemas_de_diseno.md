# Sistemas de Diseno

- Un sistema de diseno es la fuente unica de verdad visual y de comportamiento para un producto
- Arquitectura de tokens en tres niveles: marca (abstractos), semanticos (proposito), componente (especificos)
- Ejemplo: blue-500 (marca) → "primary" (semantico) → "button-bg" (componente)
- Componentes se construyen con: estilos base, variantes, tamanos, estados y overrides
- Variables CSS permiten temas dinamicos, modo oscuro y multimarca sin duplicar componentes
- Cada componente documenta: proposito, variantes, propiedades, estados, guia de accesibilidad
- Gobernanza: versionado, changelog, proceso claro para proponer cambios
- Primitivos headless ofrecen comportamiento accesible built-in y libertad visual total
- Composicion sobre configuracion: construir complejos combinando primitivos simples
- Handoff diseno-desarrollo se optimiza cuando tokens y nombres coinciden entre Figma y codigo

## Estrategias de tematizacion
- CSS Variables: maxima portabilidad, compatible con SSR, framework-agnostico
- Utility-first con variantes tipadas: eficiente con Tailwind, type-safe con CVA
- CSS-in-JS: tematizacion en runtime, estilos escopados, costo de rendimiento

## Anti-patrones
- Valores hardcodeados en vez de tokens semanticos
- Componentes sin estados de focus, hover, disabled o error
- Sistema sin documentacion ni guias de uso
