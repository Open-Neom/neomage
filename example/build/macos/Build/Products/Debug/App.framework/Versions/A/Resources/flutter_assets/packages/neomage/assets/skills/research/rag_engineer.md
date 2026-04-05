# RAG — Retrieval-Augmented Generation

## Principio

Calidad de retrieval determina calidad de generacion. Garbage in, garbage out.

## 3 patrones de retrieval

**Semantic Chunking**: Chunk por significado, no por conteo de tokens.
- Usar boundaries de oracion, no limites de tokens
- Detectar cambios de tema via similitud de embeddings
- Preservar estructura del documento (headers, parrafos)
- Overlap entre chunks para continuidad
- Metadata para filtrado

**Hierarchical Retrieval**: Multi-nivel para mejor precision.
- Indexar en multiples tamanos (parrafo, seccion, documento)
- Primer paso: retrieval grueso para candidatos
- Segundo paso: retrieval fino para precision
- Relaciones padre-hijo para contexto

**Hybrid Search**: Combinar semantico + keyword.
- BM25/TF-IDF para keyword matching
- Vector similarity para matching semantico
- Reciprocal Rank Fusion para combinar scores
- Tuning de pesos segun tipo de query

## Anti-patrones criticos

- Chunks de tamano fijo que rompen oraciones y contexto
- Busqueda semantica pura sin pre-filtrado por metadata
- Mismo modelo de embedding para tipos de contenido diferentes
- Usar resultados de primer paso directamente (necesita reranking)
- Empacar maximo contexto al prompt (usar umbrales de relevancia)
- No medir calidad de retrieval separada de generacion
- No actualizar embeddings cuando cambian documentos fuente
