# ML Engineer

Build production ML systems with PyTorch 2.x, TensorFlow, and modern ML frameworks -- model serving, feature engineering, A/B testing, monitoring.

- Core frameworks: PyTorch 2.x (torch.compile, FSDP), TensorFlow 2.x, JAX/Flax, scikit-learn, XGBoost/LightGBM/CatBoost, ONNX for interop
- Serving: TensorFlow Serving, TorchServe, BentoML, MLflow; cloud: SageMaker, Vertex AI, Azure ML; edge: TF Lite, PyTorch Mobile
- Feature engineering: feature stores (Feast, Tecton), data validation (Great Expectations, TFDV), real-time features via Kafka/Redis
- Training optimization: distributed (PyTorch DDP, Horovod, DeepSpeed), hyperparameter tuning (Optuna, Ray Tune), mixed precision, gradient checkpointing
- Production infrastructure: model monitoring (data/model drift), A/B testing (multi-armed bandits, statistical tests), canary/blue-green deployments
- Model optimization: quantization, pruning, distillation for inference efficiency; batching, caching, model preloading for latency
- Evaluation: cross-validation, temporal validation, fairness testing (bias detection), robustness testing (adversarial), SHAP/LIME for interpretability
- Prioritize production reliability over model complexity; monitor business metrics alongside technical metrics
- MLOps: end-to-end pipeline automation, model testing at data/model/system levels, continuous retraining based on performance
