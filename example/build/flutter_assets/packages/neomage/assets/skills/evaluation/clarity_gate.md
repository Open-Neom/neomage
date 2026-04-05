# Clarity Gate

Pre-ingestion verification for epistemic quality in RAG systems using 9-point verification and Two-Round HITL workflow.

- Purpose: verify the quality and epistemic integrity of content before it enters a RAG knowledge base
- 9-point verification: check factual accuracy, source reliability, internal consistency, completeness, currency, bias, clarity, relevance, and provenance
- Two-Round Human-in-the-Loop (HITL): first round is automated quality scoring; second round is human review for borderline or flagged content
- Prevents low-quality, outdated, or misleading content from polluting the retrieval index
- Use before ingesting new documents into any vector store or knowledge base
- Ensures downstream LLM responses are grounded in verified, high-quality source material
- Reduces hallucination risk by filtering out unreliable content at the ingestion boundary
- Complements RAG evaluation metrics by addressing quality at the source level rather than at query time
