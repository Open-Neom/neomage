# LLM Application Patterns

Production-ready patterns for building LLM applications: RAG pipelines, agent architectures, prompt management, and LLMOps.

- RAG pipeline: Ingest (chunking + embedding) -> Retrieve (vector/hybrid search) -> Generate (LLM + context)
- Chunking: 512 tokens with 50 overlap; strategies: fixed-size, semantic, recursive, document-aware
- Retrieval strategies: semantic search, hybrid search (dense + BM25 with RRF merge), multi-query (generate variations), contextual compression
- Agent architectures: ReAct (reason-act-observe loop), Function Calling (structured tool use), Plan-and-Execute (plan then iterate), Multi-Agent (specialized roles + coordinator)
- Prompt management: template system with variables, few-shot examples, versioning, A/B testing, chaining (output of one becomes input of next)
- LLMOps metrics: latency (p50/p99), tokens/second, user satisfaction, task completion rate, hallucination rate, cost per request, cache hit rate, error rate
- Caching: hash prompt+model+params for cache key; only cache deterministic outputs (temperature=0)
- Rate limiting with sliding window; retry with exponential backoff; fallback chain across models
- Architecture decision matrix: Simple RAG (low complexity/cost), Hybrid RAG (medium), ReAct Agent (medium), Plan-Execute (high), Multi-Agent (very high)
