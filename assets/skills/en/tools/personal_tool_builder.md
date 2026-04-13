# Personal Tool Builder

Build custom tools that solve your own problems first, then evolve into products if others share the same need.

- Good itches: "I do this manually 10x/day", "this takes 30 minutes every time", "why doesn't this exist?"
- Bad itches: "people should want this", "this would be cool", "there's a market for..."
- Start ugly: Day 1 is a script with hardcoded paths that just works; Week 1 handles your edge cases; Month 1 gets basic docs
- The 10-minute test: describe problem in one sentence, experience it weekly, tried manual solutions, would use daily
- CLI stacks: Node.js (Commander + Chalk + Inquirer) or Python (Click); distribute via npm/pip/Homebrew
- Local-first architecture: SQLite or JSON files, works offline, no server costs, your data stays yours
- Anti-patterns: building for imaginary users, over-engineering, not dogfooding your own tool daily
- Refactor only when it hurts; ugly but working always beats pretty but incomplete
- Security matters even for personal tools: sanitize inputs, handle credentials properly
