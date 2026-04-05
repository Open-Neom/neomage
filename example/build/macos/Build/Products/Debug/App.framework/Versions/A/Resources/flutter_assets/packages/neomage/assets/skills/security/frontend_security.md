# Frontend Security

Client-side security: XSS prevention, CSP, clickjacking protection, and secure browser patterns.

- Always prefer textContent over innerHTML; sanitize dynamic HTML with DOMPurify before rendering
- Content Security Policy: use nonce-based script-src, eliminate inline scripts, deploy in report-only mode first
- Clickjacking: set X-Frame-Options DENY and CSP frame-ancestors; use Intersection Observer for overlay detection
- Input validation: allowlist-based client-side validation, enforce patterns, prevent ReDoS with safe regex
- Secure redirects: validate URLs against an allowlist, use fixed destination mapping, block open redirects
- Token storage: prefer httpOnly cookies over localStorage; if using localStorage, add XSS mitigations
- Session management: sync logout across tabs via storage events, enforce idle timeouts, rotate tokens
- External links: always add rel="noopener noreferrer" to target="_blank" links
- SRI: add integrity hashes to all CDN-loaded scripts and stylesheets with fallback mechanisms
- Trusted Types: configure policies for DOM sinks to prevent injection at the API level
- CSS injection: validate dynamic style properties, avoid CSS expressions, use CSP style-src directives
