# Explicacion y Documentacion de Codigo

- El codigo se lee 10x mas de lo que se escribe; optimizar para comprension del lector
- Nombres descriptivos eliminan necesidad de comentarios: `calculateMonthlyRevenue()` > `calc()`
- Comentarios explican POR QUE, no QUE; el codigo dice que hace, los comentarios dicen por que lo hace asi
- Docstrings en funciones publicas: proposito, parametros, retorno, excepciones, ejemplo de uso
- README del modulo: que hace, como se usa, dependencias, decisiones de diseno clave

## Niveles de documentacion
- **Inline**: solo para logica no obvia, workarounds, o decisiones contraintuitivas
- **Funcion/Clase**: docstring con contrato (pre/post condiciones)
- **Modulo**: README con arquitectura local y flujo de datos
- **Sistema**: diagramas C4, ADRs, guia de contribucion

## Generacion asistida por IA
- Generar docstrings a partir de la firma y cuerpo de la funcion
- Generar diagramas de secuencia desde trazas de codigo
- Revisar documentacion existente vs codigo actual para detectar desincronizacion
- Generar explicaciones en lenguaje natural de algoritmos complejos

## Anti-patrones
- Comentarios que repiten el codigo: `i++ // increment i`
- Documentacion obsoleta que contradice el comportamiento actual
- Sobre-documentar codigo trivial, sub-documentar logica compleja
