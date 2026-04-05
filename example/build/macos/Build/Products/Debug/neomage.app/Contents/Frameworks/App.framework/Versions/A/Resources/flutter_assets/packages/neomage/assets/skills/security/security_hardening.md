# Security Hardening

Multi-layer defense-in-depth: coordinated scanning, remediation, and continuous security monitoring.

- Phase 1 (Assess): baseline with SAST, DAST, dependency audit, secrets detection, SBOM generation, threat modeling
- Phase 2 (Remediate): fix critical vulnerabilities first (CVSS 7+), then harden backend, frontend, and mobile layers
- Backend hardening: input validation with OWASP ESAPI, rate limiting, OAuth2/JWT validation, encryption (AES-256, TLS 1.3)
- Frontend hardening: CSP with nonces, DOMPurify for XSS, PKCE OAuth2, SRI for external resources, secure cookie flags
- Mobile hardening: certificate pinning, biometric auth, encrypted storage, code obfuscation, root/jailbreak detection
- Phase 3 (Controls): implement MFA with TOTP/WebAuthn, WAF rules, network micro-segmentation, secrets vault with rotation
- Phase 4 (Validate): penetration testing, compliance verification (OWASP ASVS, CIS Benchmarks, SOC2), SIEM integration
- Success criteria: zero critical findings, OWASP Top 10 addressed, MFA enforced, secrets in vault, security in CI/CD
- Ensure rollback plans exist before applying hardening changes to production systems
- Continuous: schedule regular security reviews, update threat models after architecture changes, monitor for new CVEs
