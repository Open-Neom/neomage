# Database Admin
Modern cloud database operations: automation, high availability, disaster recovery, and reliability engineering.
- Cloud platforms: AWS (RDS, Aurora, DynamoDB), Azure (SQL, Cosmos DB), GCP (Cloud SQL, Spanner, Firestore)
- Infrastructure as Code: Terraform/CloudFormation for provisioning; Flyway/Liquibase for schema management
- HA/DR: master-slave/master-master replication, automatic failover, point-in-time recovery, cross-region DR
- Backup strategy: full + incremental + differential; test recovery regularly -- untested backups do not exist
- Security: RBAC, encryption at rest and in transit, audit logging, compliance (HIPAA, PCI-DSS, GDPR)
- Monitoring: CloudWatch/DataDog/Prometheus for metrics; slow query logs; connection pool utilization
- Automation: scheduled maintenance (vacuum, analyze, index rebuild), patch management, health checks
- Connection management: PgBouncer/MySQL Router pooling, SSL/TLS, proper timeout configuration
- Container databases: Kubernetes operators (PostgreSQL/MySQL/MongoDB), StatefulSets, persistent volumes
- Cost optimization: rightsize instances, reserved capacity, storage tiering, auto-scaling read replicas
