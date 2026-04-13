# Sistemas de Memoria para Agentes

## Insight central

Memoria NO es almacenamiento — es RETRIEVAL. Un millon de hechos almacenados no significan nada si no puedes encontrar el correcto. Los fallos de memoria parecen fallos de inteligencia.

## Tipos de memoria

**Short-term (Working Memory)**: Ventana de contexto actual. Limitada por tokens. Volatil entre sesiones.

**Long-term (Semantic)**: Hechos y conocimiento persistente. Vector stores o key-value. Necesita chunking y embedding estrategico.

**Episodic**: Experiencias y eventos pasados. "La ultima vez que el usuario pregunto X, prefirio Y". Temporal y contextual.

**Procedural**: Como hacer cosas. Patrones aprendidos, workflows exitosos. Menos consultada pero critica para consistencia.

## Patrones de retrieval

**Vector Store Selection**: Elegir base de datos vectorial segun:
- Tamano del dataset
- Requisitos de latencia
- Necesidad de filtrado por metadata
- Frecuencia de actualizacion

**Chunking Strategy**: Romper documentos en chunks recuperables.
- Por significado semantico (no tamano fijo)
- Respetar estructura del documento
- Overlap para continuidad
- Metadata rica para filtrado pre-retrieval

## Anti-patrones

- Almacenar todo para siempre (sin decadencia = ruido creciente)
- Chunking sin probar retrieval
- Un solo tipo de memoria para todos los datos
- Filtrado solo por similitud vectorial (agregar metadata filtering primero)
- No trackear temporal scoring (hechos recientes > viejos)
- Ignorar conflictos en storage (detectar y resolver contradicciones)

## Principio de presupuesto

Asignar tokens para diferentes tipos de memoria. No todo merece estar en contexto activo. Just-in-time retrieval > pre-carga exhaustiva.
