# RAG Implementation

Build Retrieval-Augmented Generation systems that provide accurate, grounded LLM responses using external knowledge.

- Core components: vector database (Pinecone/Weaviate/Milvus/Chroma/Qdrant/FAISS), embeddings (OpenAI/sentence-transformers/BGE/E5), retrieval, reranking, generation
- Retrieval strategies: dense (semantic similarity), sparse (BM25/TF-IDF), hybrid (combine with RRF), multi-query (generate variations), HyDE (hypothetical documents)
- Reranking: cross-encoders for accuracy, Cohere Rerank API, MMR for diversity+relevance balance, LLM-based scoring
- Chunking: recursive character splitting (try separators in order), token-based (512 tokens, 50 overlap), semantic (by embedding similarity), markdown header splitting
- Advanced patterns: parent document retriever (small chunks for retrieval, large for context), contextual compression (extract only relevant parts), metadata filtering
- RAG prompt: ground responses in context only; instruct to say "I don't have enough information" when context is insufficient
- Include citations: return source documents with metadata for transparency and debugging
- Evaluation: measure accuracy, retrieval quality (relevant docs retrieved), and groundedness (answer based on context)
- Best practices: 500-1000 token chunks, 10-20% overlap, rich metadata (source/page/timestamp), hybrid search, reranking, continuous monitoring
- Common issues: poor retrieval (check embeddings/chunk size), irrelevant results (add metadata filtering), hallucinations (strengthen grounding prompt)
