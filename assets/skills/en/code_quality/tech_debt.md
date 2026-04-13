# Technical Debt Analysis

Identify, quantify, and prioritize technical debt to create actionable remediation plans with clear ROI.

- Inventory all debt types: code (duplication, complexity, poor structure), architecture, testing, docs, infrastructure
- Quantify impact: calculate hours lost per month and annual cost for each debt item
- Risk-rank items: critical (security, data loss) > high (perf, outages) > medium (velocity) > low (style)
- Prioritize by ROI: quick wins first (high value, low effort), then medium-term, then long-term
- Use incremental refactoring with facade and feature-flag patterns for safe migration
- Prevent new debt with automated quality gates: complexity limits, coverage minimums, dependency audits
- Track metrics over time: debt score, bug rate, deployment frequency, test coverage trends
