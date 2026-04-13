# ML Pipeline Workflow

End-to-end MLOps pipeline orchestration from data preparation through model training, validation, and deployment.

- Pipeline stages: data_ingestion -> data_validation -> feature_engineering -> model_training -> model_validation -> model_deployment
- Design principles: modularity (each stage independently testable), idempotency (safe to re-run), observability (log metrics everywhere), versioning (data + code + model)
- Data preparation: validate with Great Expectations/TFX, version datasets with DVC, document feature transformations, track data lineage
- Training: orchestrate jobs with Airflow/Dagster/Kubeflow, manage hyperparameters, track experiments (MLflow/W&B), support distributed training
- Validation: run test suite against baseline, detect performance regressions, generate comparison reports, gate deployment on quality thresholds
- Deployment: canary releases, blue-green strategy, shadow deployments for validation, automated rollback triggers
- Progressive complexity: Level 1 (linear pipeline) -> Level 2 (add validation/monitoring) -> Level 3 (hyperparameter tuning) -> Level 4 (A/B testing) -> Level 5 (multi-model ensemble)
- Orchestration tools: Apache Airflow (DAG-based), Dagster (asset-based), Kubeflow (K8s-native), Prefect (modern dataflow)
- Troubleshooting: check dependencies and data availability, validate inputs/outputs at boundaries, test components in isolation
