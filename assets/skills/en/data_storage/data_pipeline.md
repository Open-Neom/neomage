# Data Pipeline Architecture
Design scalable batch and streaming data pipelines with quality checks, orchestration, and cost optimization.
- Architecture patterns: ETL (transform first), ELT (load then transform), Lambda (batch+speed), Kappa (stream-only), Lakehouse (unified)
- Batch ingestion: incremental loading with watermark columns, retry with backoff, schema validation, dead letter queues
- Streaming: Kafka with exactly-once semantics, manual offset commits in transactions, windowing for time aggregations
- Orchestration: Airflow (task groups, XCom, SLA monitoring) or Prefect (task caching, parallel execution, artifacts)
- Transformation with dbt: staging (incremental, dedup), marts (dimensional models), tests (unique, not_null, relationships)
- Storage: Delta Lake or Iceberg with ACID transactions, time travel, file compaction, and Z-order clustering
- Data quality: Great Expectations for validation checkpoints; dbt tests for schema and custom quality rules
- Monitoring: track records processed/failed, execution time, data freshness; alert on anomalies
- Cost optimization: partition by date (keep >1GB partitions), Parquet at 512MB-1GB, lifecycle policies, spot instances
- Success: meets SLA, >99% quality pass rate, automatic retry/alerting, end-to-end lineage tracked
