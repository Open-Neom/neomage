# Executing Plans

Load, review, and execute implementation plans in batches with review checkpoints.

- Step 1 (Load and Review): read the plan file, identify concerns or questions, raise them before starting
- Step 2 (Execute Batch): work through first 3 tasks; for each, mark in-progress, follow steps exactly, run verifications, mark complete
- Step 3 (Report): after each batch, show what was implemented, show verification output, say "Ready for feedback"
- Step 4 (Continue): apply feedback changes, execute next batch, repeat until all tasks are complete
- Stop immediately when: hit a blocker (missing dependency, test fails, unclear instruction), plan has critical gaps
- Ask for clarification rather than guessing; never force through blockers
- Follow plan steps exactly; do not skip verifications or reorder tasks without explicit approval
- Between batches: report and wait for review; do not proceed without checkpoint confirmation
- After all tasks complete: verify tests pass, present completion summary, document any residual items
