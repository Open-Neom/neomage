# App Builder

Full-stack application building orchestrator that analyzes requests, determines tech stack, plans structure, and coordinates implementation.

- Detect project type from user request keywords: social app, SaaS, API, mobile, CLI, etc.
- Select appropriate tech stack: Next.js for web, FastAPI for Python APIs, Flutter/React Native for mobile, Electron for desktop
- Plan structure: database schema, API routes, pages/screens, and UI components
- Coordinate work across concerns: frontend, backend, database, and devops
- Available templates: Next.js fullstack/SaaS/static, Nuxt, Express API, FastAPI, React Native, Flutter, Electron, Chrome extension, CLI, monorepo
- Read only the files relevant to the current request from the content map
- Process: detect project type, choose stack, create plan with dependency graph, scaffold, coordinate agents, report progress
