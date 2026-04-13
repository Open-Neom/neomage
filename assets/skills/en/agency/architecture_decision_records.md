# ADR — Architecture Decision Records

## Proposito

Documentar decisiones tecnicas importantes con contexto, alternativas y razonamiento para referencia futura.

## Template MADR (Minimal)

```
# ADR-NNN: Titulo de la Decision

## Estado
[Propuesto | Aceptado | Deprecado | Reemplazado por ADR-XXX]

## Contexto
Que situacion motiva esta decision. Fuerzas en juego.

## Decision
Lo que decidimos hacer.

## Consecuencias
Positivas, negativas, y neutrales. Trade-offs aceptados.
```

## Template Y-Statement (Compacto)

"En el contexto de [contexto], frente a [concern], decidimos [decision] para lograr [objetivo], aceptando [trade-off]."

## Cuando crear ADR

- Eleccion de tecnologia/framework
- Patron arquitectonico significativo
- Decision que limita opciones futuras
- Compromiso entre requisitos en conflicto
- Desviacion de practicas establecidas

## Ciclo de vida

1. Propuesto → discusion abierta
2. Aceptado → implementar
3. Deprecado → ya no aplica pero se mantiene como registro
4. Reemplazado → nueva decision toma precedencia (linkar)

## Regla de oro

Si en 6 meses alguien preguntara "por que hicimos esto?", deberia existir un ADR que lo explique.
