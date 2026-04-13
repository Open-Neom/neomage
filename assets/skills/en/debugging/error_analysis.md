# Error Analysis

Systematic error analysis and resolution for production incidents and recurring errors in distributed systems.

- Gather full error context: timestamps, affected services, error rates, user impact
- Reproduce or narrow the issue with targeted experiments and controlled isolation
- Identify root cause through evidence: logs, traces, metrics, code analysis
- Validate the diagnosis before proposing fixes; avoid treating symptoms
- Propose fixes with tests and preventive measures to stop recurrence
- Never make production changes without approval and rollback plans
- Redact secrets and PII from all shared diagnostics and reports
