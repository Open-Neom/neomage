# Smart Debug

AI-assisted debugging combining observability platforms, pattern recognition, and automated root cause analysis.

- Parse the issue for: error messages, stack traces, repro steps, affected services, environment, failure pattern
- Initial triage: generate 3-5 ranked hypotheses with probability scores and falsification criteria
- Gather observability data: error tracking, APM metrics, distributed traces, log aggregation
- Select strategy by issue type: interactive debugging (local), observability-driven (prod), time-travel (state), chaos (intermittent), statistical (edge cases)
- Place instrumentation at: entry points, decision nodes, state mutations, integration boundaries, error paths
- Production-safe techniques: feature-flagged debug logging, sampling-based profiling, canary deployments
- Root cause analysis: reconstruct execution path, track variable state, identify similar past bugs
- Post-fix: run test suite, compare performance baseline, canary deploy, add regression tests and monitoring
