# Compresion de Contexto — Estrategias para Sesiones Largas

## Insight central

Optimizar tokens-por-tarea, NO tokens-por-request. Ahorrar 0.5% mas tokens pero causar 20% mas re-fetching cuesta mas en total.

## 3 metodos de compresion

**Anchored Iterative Summarization** (Recomendado):
- Mantener resumenes estructurados persistentes con secciones explicitas
- Al trigger, resumir solo el span recien truncado
- Merge con resumen existente (no regenerar completo)
- La estructura fuerza preservacion: secciones actuan como checklist
- 98.6% compresion, 3.70 calidad

**Opaque Compression**:
- Representaciones comprimidas optimizadas para fidelidad de reconstruccion
- Maxima compresion (99.3%) pero sacrifica interpretabilidad
- No se puede verificar que se preservo
- 99.3% compresion, 3.35 calidad

**Regenerative Full Summary**:
- Resumenes detallados estructurados en cada compresion
- Legible pero pierde detalles en ciclos repetidos de compresion
- 98.7% compresion, 3.44 calidad

## Secciones de resumen estructurado

```
## Intencion de Sesion
[Que intenta lograr el usuario]

## Archivos Modificados
- archivo.dart: Descripcion del cambio

## Decisiones Tomadas
- Decision y razon

## Estado Actual
- Estado de tests, errores pendientes

## Siguientes Pasos
1. Paso concreto
```

La estructura previene perdida silenciosa de paths o decisiones.

## Problema del Artifact Trail

Dimension mas debil en todos los metodos (2.2-2.5 de 5.0). Agentes necesitan saber:
- Archivos creados/modificados/leidos
- Nombres de funciones, variables, mensajes de error
→ Requiere tracking separado: indice de artifacts o tracking explicito.

## Triggers de compresion

| Estrategia | Trigger | Trade-off |
|-----------|---------|-----------|
| Umbral fijo | 70-80% utilizacion | Simple pero puede comprimir temprano |
| Ventana deslizante | Ultimos N turnos + resumen | Tamano predecible |
| Basado en importancia | Comprimir baja-relevancia primero | Complejo pero preserva senal |
| Frontera de tarea | Comprimir al completar tarea logica | Resumenes limpios |

## Evaluacion por sondeo

No usar ROUGE ni embedding similarity (no capturan calidad funcional).
Preguntas post-compresion:
- Recall: "Cual fue el error original?"
- Artifact: "Que archivos modificamos?"
- Continuacion: "Que sigue?"
- Decision: "Que decidimos sobre X?"

## Flujo de 3 fases para codebases grandes

1. **Research**: Explorar → documento de analisis estructurado
2. **Planning**: Research → especificacion con firmas, tipos, flujo de datos (~2000 palabras para 5M tokens)
3. **Implementation**: Ejecutar contra la especificacion (contexto enfocado)
