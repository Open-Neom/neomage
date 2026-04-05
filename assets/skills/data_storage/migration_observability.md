# Migration Observability
Monitor database migrations in real-time with CDC pipelines, anomaly detection, and automated alerting.
- Instrument migrations with Prometheus metrics: duration histograms, documents/rows processed counters, error counters
- Change Data Capture (CDC) with Debezium + Kafka for real-time source-to-target synchronization
- Track CDC metrics: events processed (by source/table/operation), consumer lag, replication lag
- Anomaly detection: alert when throughput drops below 50% of expected, or error rate exceeds 1%
- Grafana dashboards: migration progress (rows/sec), data lag (seconds), error rate, overall health
- Multi-channel alerting: Slack, email, PagerDuty with severity levels (critical, warning, info)
- Wrap migration execution in transactions with structured logging (Winston/similar)
- CI/CD integration: start monitoring before migration, run migration, check health after completion
- Track migration state across the entire lifecycle: started, running, validating, completed, or failed
- Focus on real-time visibility and proactive alerting for zero-downtime migrations
