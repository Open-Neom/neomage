# Security Requirement Extraction

Transform threat models and business context into actionable security requirements.

- Input: threat model findings, business context, compliance requirements, architecture documentation
- For each identified threat, derive specific, testable security requirements with acceptance criteria
- Format as security user stories: "As [role], I need [control] so that [threat] is mitigated"
- Categorize requirements: authentication, authorization, data protection, input validation, logging, availability
- Priority: map requirement priority to threat severity and business impact (critical threats get mandatory requirements)
- Traceability: maintain bidirectional links between threats, requirements, controls, and test cases
- Test cases: for each requirement, define positive tests (control works) and negative tests (attack is blocked)
- Compliance mapping: tag each requirement with applicable regulatory controls (GDPR Art. 32, PCI-DSS Req. 6, etc.)
- Acceptance criteria must be verifiable: specify exact behaviors, thresholds, and measurable outcomes
- Review requirements when architecture changes, new threats emerge, or compliance landscape shifts
