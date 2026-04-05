# Context-Driven Development

Treat project context as a first-class artifact managed alongside code for consistent AI interactions and team alignment.

- Core principle: context precedes code -- define what you're building and how before implementation
- Key artifacts: product.md (WHAT/WHY), tech-stack.md (WITH WHAT), workflow.md (HOW to work), product-guidelines.md (HOW to communicate), tracks.md (WHAT'S HAPPENING)
- Workflow: Context phase -> Specification phase -> Planning phase -> Implementation phase
- Living documentation: artifacts evolve with the project; update as features complete, dependencies change, or practices evolve
- Keep artifacts synchronized: new feature in product.md may require tech-stack.md update; completed track updates product.md
- Verify context before every implementation: read all artifacts, flag outdated info, propose updates before proceeding
- Anti-patterns: stale context (outdated docs), context sprawl (info scattered), implicit context (undocumented knowledge), over-specification (impossible to maintain)
- Greenfield: create artifacts interactively from scratch; Brownfield: analyze existing code to pre-populate artifacts
- Session continuity: start by reading index.md + tracks.md; end by updating plan.md with progress and blockers
- Benefits: faster onboarding, consistent AI outputs across sessions, preserved institutional memory, explicit quality gates
