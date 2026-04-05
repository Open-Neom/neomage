# Cloud Cost Optimization
Reduce cloud spending across AWS, Azure, and GCP through rightsizing, reserved capacity, and architecture optimization.
- Four pillars: visibility (tagging, dashboards, budgets), rightsizing, pricing models, architecture optimization
- Reserved instances save 30-72% vs on-demand; savings plans are more flexible across services
- Spot/preemptible instances save up to 90% for batch jobs, CI/CD, and stateless workloads
- S3/storage lifecycle policies: Standard -> Standard-IA (30d) -> Glacier (90d) -> Deep Archive (365d)
- Auto-scaling: scale based on metrics (CPU, queue depth), use cooldown periods, mix instance types
- Implement cost allocation tags on every resource: Environment, Project, CostCenter, Owner, ManagedBy
- Set budget alerts at 80% threshold; enable cost anomaly detection across all accounts
- Serverless-first for event-driven workloads: pay only for execution, auto-scaling included, no idle cost
- Delete unused resources: unattached EBS volumes, unused EIPs, old snapshots, idle load balancers
- Review costs weekly; use cloud-native tools (Cost Explorer, Advisor, Recommender) plus multi-cloud tools
