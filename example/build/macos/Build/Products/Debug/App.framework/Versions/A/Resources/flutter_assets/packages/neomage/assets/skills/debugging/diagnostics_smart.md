# Smart Diagnostics Debug

AI-powered debugging combining automated triage, observability data, and hypothesis-driven root cause analysis.

- Parse issue details: error messages, stack traces, repro steps, affected components, failure patterns
- Generate ranked hypotheses with probability scores, evidence, and falsification criteria
- Common root cause categories: logic errors, state management, integration failures, resource exhaustion, config drift, data corruption
- Strategy selection: interactive (local repro), observability-driven (production), time-travel (state bugs), chaos (intermittent), statistical (rare cases)
- Instrument at decision nodes, state mutations, and integration boundaries
- Production-safe: dynamic instrumentation, feature-flagged logging, sampling profilers, canary deploys
- Post-fix: validate with test suite, performance baseline comparison, regression test generation
