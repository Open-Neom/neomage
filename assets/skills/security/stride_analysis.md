# STRIDE Analysis

Systematic threat identification using the STRIDE methodology for security design review.

- STRIDE categories: Spoofing, Tampering, Repudiation, Information Disclosure, Denial of Service, Elevation of Privilege
- Process: define system scope, create data flow diagrams, identify trust boundaries, apply STRIDE to each component/flow
- Spoofing: can an attacker impersonate a user or service? Mitigate with strong authentication and mutual TLS
- Tampering: can data be modified in transit or at rest? Mitigate with integrity checks, signing, and encryption
- Repudiation: can actions be denied? Mitigate with audit logs, digital signatures, and tamper-evident logging
- Information Disclosure: can sensitive data leak? Mitigate with encryption, access controls, and data classification
- Denial of Service: can availability be disrupted? Mitigate with rate limiting, redundancy, and resource quotas
- Elevation of Privilege: can low-privilege users gain high access? Mitigate with least privilege, input validation, sandboxing
- Focus on data flows and trust boundaries, not just individual components; consider insider threats
- Document findings in a threat matrix with likelihood, impact, existing controls, and recommended mitigations
- Update STRIDE analysis when architecture changes or new features add trust boundaries
