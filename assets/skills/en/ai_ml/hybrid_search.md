# Hybrid Search Implementation

Combine vector similarity search and keyword-based search for improved retrieval in RAG systems and search engines.

- Pure vector search misses exact keyword matches; pure keyword search misses semantic meaning; hybrid combines both strengths
- Use when queries contain specific terms (names, codes, IDs) alongside natural language intent
- Essential for domain-specific vocabulary where embeddings may lack specialized training
- Combine results using reciprocal rank fusion (RRF) or weighted score merging
- Tune the balance between vector and keyword scores based on query type and domain
- BM25 or TF-IDF handles the keyword component; dense embeddings handle the semantic component
- Index both representations at ingestion time to avoid query-time overhead
- Evaluate with recall and precision metrics; hybrid typically improves recall over either method alone
- Particularly valuable for RAG systems where missing a relevant chunk degrades generation quality
