# Vector Index Tuning

Optimize vector index performance for latency, recall, and memory in production search systems.

- Gather workload targets first: latency SLA, recall requirement, QPS, data size, memory budget
- Start with default parameters, establish a baseline, then benchmark parameter sweeps with real queries
- HNSW tuning: M (connections per node, higher = better recall, more memory), efConstruction (build quality), efSearch (query quality vs speed)
- Quantization strategies: Product Quantization (PQ) for memory reduction, Scalar Quantization for speed, binary quantization for extreme compression
- Tradeoff spectrum: flat index (exact, slow) -> IVF (approximate, fast) -> HNSW (good balance) -> HNSW+PQ (memory-efficient, some recall loss)
- Validate changes on staging dataset with realistic load before production rollout
- Always have a rollback plan before reindexing in production
- Track recall regressions: if quality drops after parameter changes, revert immediately
- Use ground truth query sets to measure recall accurately at each tuning step
- Balance recall, latency, and memory -- optimizing one often degrades another
