# C4 Container Level
Map components to deployment units, document APIs, and show system deployment architecture.
- Containers are separately deployable units: web apps, APIs, databases, message queues, file systems
- Each container: name, type, technology stack, deployment method, and purpose
- Show high-level technology choices at this level -- this is where tech details belong in C4
- Document all container interfaces as APIs with OpenAPI/Swagger specifications
- Show communication protocols between containers (HTTP, gRPC, AMQP, SQL, etc.)
- Include infrastructure details: deployment config links, scaling strategy, resource requirements
- Link to all contained components for drill-down navigation
- Use C4Container Mermaid notation showing system boundary, containers, and external systems
- Map to actual deployment definitions: Dockerfiles, K8s manifests, Terraform configs
- Include external systems the containers interact with and their integration types
