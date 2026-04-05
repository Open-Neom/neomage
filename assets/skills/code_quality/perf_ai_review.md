# Performance-Focused AI Review

AI-powered code review with emphasis on performance analysis, scalability issues, and optimization opportunities.

- Combine static analysis (CodeQL, SonarQube, Semgrep) with AI contextual review for performance focus
- Detect scalability red flags: N+1 queries, missing indexes, synchronous external calls, unbounded collections
- Profile and compare baseline vs. PR branch for CPU, memory, and latency regressions
- Classify issues by severity with file:line references and concrete fix examples
- Route review depth by PR size and sensitivity; deep analysis for performance-critical paths
- Check architectural coherence: dependency direction, SOLID adherence, microservices boundaries
- Integrate with CI/CD as quality gates; block PRs with critical performance regressions
