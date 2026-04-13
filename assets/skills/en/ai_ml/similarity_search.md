# Similarity Search Patterns

Implement efficient similarity search in production for semantic search, RAG retrieval, and recommendation engines.

- Use when building semantic search, implementing RAG retrieval, creating recommendation engines, or scaling to millions of vectors
- Core approach: embed queries and documents in shared vector space, retrieve by similarity (cosine, dot product, Euclidean)
- Combine semantic search with keyword search (hybrid) for best results across different query types
- Optimize for latency vs recall tradeoffs based on production requirements
- Scale considerations: index type selection, sharding, caching frequent queries, batch processing
- Clarify goals (latency target, recall target, QPS), constraints (memory budget, infrastructure), and data characteristics first
- Apply relevant best practices: normalize embeddings, batch requests, cache results, monitor drift
- Validate outcomes with representative queries and ground truth data
