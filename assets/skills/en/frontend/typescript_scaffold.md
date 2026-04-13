# TypeScript Project Scaffolding

Scaffold production-ready TS projects: Next.js, React+Vite, Node API, libraries, and CLIs with modern tooling.

- Package manager: pnpm for fast, disk-efficient installs; use pnpm workspaces for monorepos
- Project types: Next.js (SSR/SSG full-stack), React+Vite (SPA), Node.js API (Express/Fastify), Library (reusable packages), CLI (automation tools)
- tsconfig essentials: strict:true, target ES2022, moduleResolution "bundler", paths aliases (@/*), incremental builds
- Next.js: App Router with src/ directory, import alias @/*, TypeScript strict, Tailwind, Vitest for testing
- React+Vite: path aliases via vite.config resolve, jsdom test environment, Vitest with globals
- Node.js API: type:"module" in package.json, tsx for dev, express+zod for validation, layered structure (routes/controllers/services/models)
- Library: hatchling/tsc for build, dual ESM output, proper exports map with types field, prepublishOnly script
- Testing: Vitest for all project types, v8 coverage provider, globals:true for clean test syntax
- Linting: ESLint + @typescript-eslint or Biome for speed; no-explicit-any as warning, no-unused-vars as error
- Dev tools: .env.example for config documentation, .gitignore (node_modules, dist, .env), type-check script (tsc --noEmit)
