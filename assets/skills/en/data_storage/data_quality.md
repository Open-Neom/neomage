# Data Quality Frameworks
Implement data validation with Great Expectations, dbt tests, and data contracts for reliable pipelines.
- Great Expectations: table-level (row count, column count) and column-level (uniqueness, nullability, ranges, types)
- dbt tests: schema tests in YAML (unique, not_null, relationships, accepted_values), custom tests with dbt-expectations
- Data contracts: formal agreements between producer and consumer teams on schema, quality, and SLAs
- Automate validation in CI/CD pipelines; run quality checks before data reaches production sinks
- Define quality dimensions: completeness, accuracy, consistency, timeliness, uniqueness, validity
- Implement checkpoints that halt pipelines on critical failures with clear alerting
- Use data docs (Great Expectations) for automated documentation of quality rules and results
- Assign data ownership: every dataset has a responsible team for quality remediation
- Monitor quality metrics over time; detect degradation trends before they become incidents
- Handle sensitive data securely in validation outputs; avoid blocking critical pipelines without fallback
