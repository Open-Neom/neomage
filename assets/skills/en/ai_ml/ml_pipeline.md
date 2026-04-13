# ML Pipeline (Multi-Agent MLOps Orchestration)

Design end-to-end ML pipelines with multi-agent coordination across data, training, deployment, and monitoring phases.

- Phase 1 (Data): data source audit, schema validation (Pydantic/Great Expectations), data versioning (DVC/lakeFS), quality gates and SLAs
- Phase 1 (Features): feature engineering specs, feature store schema (Feast/Tecton), statistical validation, algorithm selection rationale
- Phase 2 (Training): modular training code, hyperparameter optimization (Optuna/Ray Tune), distributed training (Horovod/PyTorch DDP), experiment tracking (MLflow/W&B)
- Phase 2 (Quality): refactor for production, profile bottlenecks, unit/integration/model quality tests, memory management for large-scale training
- Phase 3 (Deploy): REST/gRPC APIs (FastAPI/TorchServe), batch pipelines (Airflow/Kubeflow), blue-green/canary/shadow deployments, CI/CD with ArgoCD GitOps
- Phase 3 (Infra): Kubernetes with GPU scheduling, HPA/VPA/KEDA autoscaling, Helm charts, Istio service mesh
- Phase 4 (Monitor): prediction accuracy tracking, drift detection (KS test, PSI), Prometheus/Grafana dashboards, automated retraining triggers, cost tracking
- Success criteria: <0.1% data quality issues, <5% performance degradation before retrain, 99.9% uptime, <200ms p99 latency, <1hr commit-to-production
- Config options: experiment tracking (mlflow/wandb), feature store (feast/tecton), serving (kserve/seldon), orchestration (kubeflow/airflow)
