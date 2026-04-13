# Dependency Vulnerability Scanning

Analyze dependencies for vulnerabilities, generate SBOMs, and secure the software supply chain.

- Scan all dependency manifests (package.json, requirements.txt, go.mod, Cargo.toml, pom.xml) and lockfiles
- SBOM generation: produce Software Bill of Materials in CycloneDX or SPDX format for supply chain visibility
- Vulnerability databases: cross-reference with NVD, GitHub Advisory, OSV, and vendor-specific advisories
- Severity triage: prioritize by CVSS score, exploitability (is there a public exploit?), and reachability in your code
- License compliance: flag copyleft licenses in commercial projects, track license obligations per dependency
- Remediation strategy: upgrade to patched versions first, apply workarounds if no patch, replace if abandoned
- Transitive dependencies: scan the full dependency tree, not just direct dependencies
- CI integration: block merges on critical/high vulnerabilities, alert on medium, track low for batch updates
- Tools: Snyk, Trivy, OWASP Dependency-Check, GitHub Dependabot, npm audit, pip-audit, cargo-audit
- Never auto-upgrade without testing; treat dependency changes as release-impacting with full regression tests
