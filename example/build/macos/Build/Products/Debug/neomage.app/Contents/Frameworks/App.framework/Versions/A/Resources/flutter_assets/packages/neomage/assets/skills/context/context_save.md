# Context Save

Comprehensive, semantic context preservation across AI workflows for multi-session collaboration and knowledge transfer.

- Captures project state: metadata, architectural decisions, dependency graphs, and semantic tags
- Input parameters: PROJECT_ROOT (path), CONTEXT_TYPE (minimal/standard/comprehensive), STORAGE_FORMAT (json/markdown/vector), TAGS (categorization)
- Extraction strategies: identify architectural patterns, capture decision rationales, map dependencies, extract implicit knowledge structures
- Serialization: JSON Schema for structured representation, nested hierarchical models, type-safe, lossless reconstruction
- Multi-session management: unique context fingerprints, version control for context artifacts, drift detection, semantic diffs
- Compression: semantic token reduction (lossy and lossless modes) to optimize storage while preserving key information
- Vector database integration: generate semantic embeddings, build vector indexes, enable similarity-based retrieval (Pinecone/Weaviate/Qdrant)
- Knowledge graph construction: extract relational metadata, create ontological representations, enable inference-based expansion
- Storage formats: structured JSON, markdown with frontmatter, Protocol Buffers, MessagePack, YAML with annotations
- Key workflows: project onboarding capture (analyze -> extract -> embed -> store -> summarize) and long-running session snapshots
