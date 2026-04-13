# Context Restoration

Intelligent, semantic-aware context retrieval and reconstruction across complex multi-agent AI workflows.

- Restoration modes: full (complete rebuild), incremental (partial update), diff (compare and merge versions)
- Semantic vector search: use multi-dimensional embeddings with cosine similarity, support text/code/diagram modalities
- Relevance filtering: multi-stage scoring combining semantic similarity, temporal decay, and historical decision impact
- Token budget management: prioritize components (overview, architectural decisions, tech stack, recent work, known issues) and load within budget
- Rehydration pattern: prioritize components, estimate tokens per component, load greedily until budget exhausted
- Session state reconstruction: preserve decision trails, reasoning contexts, and multi-agent collaboration history
- Context merging: three-way merge strategies with semantic conflict detection and provenance traceability
- Incremental loading: lazy-load components, stream context for large projects, enable dynamic expansion
- Validation: cryptographic signatures for integrity, semantic consistency verification, version compatibility checks
- Key workflows: project resumption (retrieve -> validate -> restore -> summarize) and cross-project knowledge transfer
