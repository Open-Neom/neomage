# Concise Planning

Turn coding tasks into clear, actionable plans with atomic steps and minimal interaction.

- Scan context first: read README, docs, relevant code files; identify constraints (language, frameworks, tests)
- Ask at most 1-2 questions and only if truly blocking; make reasonable assumptions for non-blocking unknowns
- Plan structure: Approach (1-3 sentences on what and why), Scope (In/Out bullets), Action Items (6-10 tasks), Validation
- Action items must be atomic: each step is a single logical unit of work, verb-first ("Add...", "Refactor...", "Verify...")
- Be concrete: name specific files and modules; "Add auth middleware to routes/auth.ts" not "Set up authentication"
- Always include at least one validation item: a test to run, a curl command, or a visual check
- Keep plans short: if longer than one page, simplify or split into multiple plans
- Open questions: list at most 3 blocking unknowns that require user input before proceeding
