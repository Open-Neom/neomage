# Mobile Security

Secure mobile development: data storage, WebView hardening, cert pinning, and platform-specific protections.

- Secure storage: use Keychain (iOS) / Keystore (Android) for credentials; encrypt local databases (SQLite, Realm)
- WebView security: disable JavaScript by default, allowlist URLs, enforce HTTPS, set CSP, clear cache on logout
- Certificate pinning: pin to leaf or intermediate cert, implement backup pins, handle rotation gracefully
- Authentication: integrate biometric (Face ID, fingerprint) with secure fallback; use PKCE for OAuth mobile flows
- Network security: enforce TLS 1.2+, reject self-signed certs, configure Android Network Security Config and iOS ATS
- Code protection: enable ProGuard/R8 (Android), use obfuscation, implement root/jailbreak detection with graceful degradation
- Deep link security: validate URL schemes and intent filters, sanitize parameters, check authorization
- Data leakage prevention: sanitize logs, block screenshots on sensitive screens, exclude sensitive files from backups
- Platform channels (Flutter/RN): validate all messages crossing native bridges, never trust data from JS side
- Privacy: minimize data collection, implement consent flows, comply with GDPR/CCPA, audit third-party SDKs
