# Memory Systems

Design short-term, long-term, and graph-based memory architectures for agent persistence and knowledge reasoning.

- Memory spectrum: working memory (context window, zero latency, volatile) -> short-term (session-persistent) -> long-term (cross-session) -> entity memory (identity tracking) -> temporal knowledge graphs (time-valid facts)
- Simple vector stores lose relationship structure and temporal validity; knowledge graphs preserve relationships; temporal graphs add validity periods
- Benchmark: Temporal KG (Zep) achieves 94.8% accuracy with 90% latency reduction; GraphRAG gives 20-35% gains over baseline RAG; recursive summarization loses 65% of information
- Implementation patterns: file-system-as-memory (simple, no infra), vector RAG with metadata (semantic search + filtering), knowledge graph (entity + relationship), temporal KG (validity periods for time-travel queries)
- Memory retrieval types: semantic (embedding similarity), entity-based (graph traversal), temporal (validity period filters)
- Consolidation: trigger after significant accumulation or periodic schedule; identify outdated facts, merge related ones, update validity periods, rebuild indexes
- Architecture selection: simple persistence -> file system; semantic search -> vector RAG; relationship reasoning -> knowledge graph; temporal validity -> temporal KG
- Integrate memory with context via just-in-time loading and strategic injection at attention-favored positions
- Design for retrieval failures gracefully; consider privacy implications of persistent memory; monitor growth over time
