# XSS Vulnerability Scanning

Detect and prevent Cross-Site Scripting across React, Vue, Angular, and vanilla JS.

- Dangerous sinks to scan for: innerHTML, outerHTML, document.write, insertAdjacentHTML, location.href, window.open
- React: flag dangerouslySetInnerHTML without DOMPurify.sanitize(); prefer JSX auto-escaping
- Vue: flag v-html directive; prefer v-text for plain text rendering
- Angular: rely on built-in sanitization; flag bypasses of DomSanitizer (bypassSecurityTrust*)
- URL injection: validate all URLs with URL constructor, enforce http/https only, block javascript: and data: protocols
- Event handlers: prefer addEventListener over inline handlers; never pass user input to eval, Function(), or setTimeout with strings
- Safe DOM manipulation: use textContent for plain text, sanitize with DOMPurify before any HTML injection
- Classify severity: innerHTML with user input is critical, unsanitized framework escape hatches are high, URL injection is high
- Prevention stack: DOMPurify for HTML sanitization, CSP headers with nonces, Trusted Types API for DOM sink protection
- Automate scanning with ESLint security plugin and Semgrep XSS rulesets in CI
