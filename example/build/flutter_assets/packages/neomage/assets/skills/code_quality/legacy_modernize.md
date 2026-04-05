# Legacy Modernization

Gradually replace outdated components using the strangler fig pattern while maintaining continuous business operations.

- Assess legacy system: inventory technical debt, map dependencies, score component complexity
- Establish test coverage before touching anything: characterization tests capture current behavior
- Implement strangler fig infrastructure: API gateway for traffic routing, feature flags for rollout
- Modernize in waves: quick wins first, then progressively harder components
- Use adapter and facade patterns to maintain backward compatibility during transition
- Validate with progressive rollout: 5% to 25% to 50% to 100% with observation periods
- Decommission legacy only after 30+ days at zero traffic with no remaining dependencies
- Success: zero unplanned downtime, performance maintained, >80% test coverage on new code
