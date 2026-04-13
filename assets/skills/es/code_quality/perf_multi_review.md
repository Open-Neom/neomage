# Multi-Agent Review Orchestration

> *Contenido tecnico en ingles para optimizar el procesamiento de la IA. El titulo y la categoria estan en espanol.*

Coordinate multiple specialized review agents for comprehensive, multi-perspective code analysis.

- Dynamically select agents based on code characteristics: security, performance, architecture, quality, compliance
- Run independent reviews in parallel; use sequential processing when insights build on each other
- Maintain shared context across agents; pass refined insights between review phases
- Aggregate results into a unified, prioritized report resolving conflicting recommendations
- Apply weighted scoring to resolve conflicts between agent recommendations
- Validate review quality with cross-agent verification and confidence scoring
- Design for extensibility: plugin architecture allows adding new agent types easily
