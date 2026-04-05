# Analytics Tracking & Measurement Strategy

Design and audit analytics systems that produce trustworthy, decision-ready data across GA4, GTM, and product analytics.

- Track for decisions, not curiosity: if no decision depends on it, do not track it
- Start with business questions, work backwards to define events and signals
- Events represent meaningful state changes (intent, completion, commitment), not cosmetic clicks
- Event naming: `object_action_context` in lowercase with underscores (e.g., `signup_completed`)
- Conversions must represent real value, completed intent, and irreversible progress
- Fewer accurate events always beat many unreliable ones
- Score measurement readiness (0-100) before adding tracking: below 55 means data is broken
- Validate tracking: check for double-firing, missing properties, broken attribution, PII leakage
- UTMs: lowercase only, consistent separators, documented centrally, never overwritten client-side
- Consent before tracking where required; analytics that violate trust undermine optimization
