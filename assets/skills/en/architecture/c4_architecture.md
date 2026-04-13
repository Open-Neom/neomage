# C4 Architecture Documentation
Generate comprehensive C4 model documentation using bottom-up analysis: Code, Component, Container, Context.
- Process bottom-up: analyze deepest directories first, then synthesize upward through C4 levels
- Code level: document every function signature, class, dependency, and relationship per directory
- Component level: group related code into logical components with clear boundaries and interfaces
- Container level: map components to deployment units (apps, databases, queues) with technology choices
- Context level: show the system, its users (human and programmatic), and external dependencies
- Container diagrams show high-level tech choices; context diagrams focus on people and systems, not tech
- Generate OpenAPI specs for each container API at the container level
- Include Mermaid diagrams at each level using proper C4 notation
- Teams only need context + container diagrams for most work; code/component levels are optional depth
- Ensure all documentation cross-links between levels for navigation
