# Embedding Strategies

Select and optimize embedding models for semantic search and RAG applications.

- Model selection: text-embedding-3-large (3072d, high accuracy), text-embedding-3-small (1536d, cost-effective), voyage-2 (code/legal), bge-large (open source), all-MiniLM-L6-v2 (fast/lightweight), multilingual-e5-large (multi-language)
- Pipeline: Document -> Chunking (size + overlap) -> Preprocessing (clean, normalize) -> Embedding Model -> Vector
- Chunking strategies: token-based (fixed size with overlap), sentence-based (respect boundaries), semantic sections (by headers), recursive character splitting (try multiple separators)
- Matryoshka dimension reduction: text-embedding-3-small supports reduced dimensions (e.g., 512) for faster search with acceptable quality loss
- BGE models benefit from query prefixes; E5 models use "query:" and "passage:" prefixes for asymmetric search
- Batch embedding requests (batch_size=100) for efficiency; cache embeddings to avoid recomputation
- Normalize embeddings for cosine similarity; never mix embedding models in the same vector space
- Evaluation metrics: precision@K, recall@K, MRR, NDCG@K -- always measure retrieval quality on representative queries
- Domain-specific pipelines: preprocess (clean whitespace, remove special chars), chunk, embed, store with metadata
- Code embeddings: use tree-sitter for function/class-level chunking; embed with surrounding context
