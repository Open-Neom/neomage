# Multi-Agent Brainstorming (Structured Design Review)

Sequential design review with enforced roles to surface hidden assumptions and validate designs before implementation.

- This is NOT parallel brainstorming; it is sequential review with strict, non-overlapping agent roles
- 5 roles: Primary Designer (owns design), Skeptic (finds weaknesses), Constraint Guardian (enforces NFRs), User Advocate (represents end user), Integrator/Arbiter (resolves conflicts)
- Each agent has hard scope limits: may NOT exceed its mandate (e.g., Skeptic may not propose features)
- Phase 1: Designer runs single-agent brainstorming, produces initial design and Decision Log
- Phase 2: Review loop -- invoke Skeptic, Constraint Guardian, User Advocate one at a time; Designer responds to each
- Phase 3: Integrator reviews final design, Decision Log, and unresolved objections; explicitly accepts or rejects each
- Decision Log is mandatory: records decisions, alternatives considered, objections, and resolutions with rationale
- Exit criteria (all must be true): Understanding Lock done, all reviewers invoked, all objections resolved, Decision Log complete, Arbiter approves
- Final disposition: APPROVED, REVISE, or REJECT with rationale
- Prevents: idea swarm chaos, hallucinated consensus, overconfident designs, hidden assumptions, premature implementation
