# LLM Evaluation

Comprehensive evaluation strategies for LLM applications: automated metrics, human feedback, LLM-as-judge, and A/B testing.

- Automated text metrics: BLEU (n-gram overlap), ROUGE (recall-oriented), METEOR (semantic similarity), BERTScore (embedding-based), Perplexity
- RAG retrieval metrics: MRR (mean reciprocal rank), NDCG (normalized discounted cumulative gain), Precision@K, Recall@K
- LLM-as-Judge approaches: pointwise scoring, pairwise comparison, reference-based, reference-free -- use stronger model to judge weaker
- Human evaluation dimensions: accuracy, coherence, relevance, fluency, safety, helpfulness -- use standardized rubrics with multiple raters
- Inter-rater agreement: measure with Cohen's kappa; aim for "substantial" (0.6-0.8) or better
- A/B testing: minimum 100 tasks per variant, 95% confidence (p<0.05), calculate Cohen's d effect size; report relative improvement
- Regression detection: flag when any metric drops >5% relative to baseline; track over time
- Custom metrics: groundedness (NLI entailment check), toxicity (Detoxify), factuality (verify against knowledge base)
- Common pitfalls: single-metric obsession, small sample sizes, data contamination, ignoring variance, metrics misaligned with business goals
- Best practice: use multiple diverse metrics, representative test data, continuous evaluation in CI/CD, and supplement automation with human review
