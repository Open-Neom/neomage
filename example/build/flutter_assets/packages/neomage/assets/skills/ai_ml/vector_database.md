# Vector Database Engineer

Design and optimize vector databases for RAG, semantic search, recommendation engines, and similarity search at scale.

- Database selection: Pinecone (managed, scalable), Weaviate (open-source, hybrid), Qdrant (fast, filtered), Milvus (high-perf, on-prem), pgvector (existing Postgres)
- Index types: HNSW (balanced speed/recall), IVF (large-scale), PQ (memory-efficient), LSH (approximate, fast)
- Embedding dimensions: choose 384-1536 based on use case; higher dimensions = better accuracy but more memory/compute
- Implement proper chunking with overlap; use metadata filtering to reduce search space before vector search
- Hybrid search: combine vector similarity with keyword matching for comprehensive retrieval
- Workflow: analyze data/query patterns -> select embedding model -> design chunking pipeline -> choose DB/index -> configure metadata schema -> implement hybrid search -> optimize latency/recall -> set up monitoring
- Monitor embedding drift over time; plan for index rebuilding as data grows
- Cache frequent queries; test recall vs latency tradeoffs with representative workloads
- Similarity metrics: cosine (normalized), dot product (unnormalized, magnitude matters), Euclidean (distance-based)
