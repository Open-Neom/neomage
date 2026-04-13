# TypeScript Expert

Type-level programming, performance optimization, monorepo management, migration strategies, and modern tooling.

- Branded types for domain modeling: prevent primitive mixing (UserId vs OrderId) at compile time with zero runtime cost
- Advanced conditionals: recursive type manipulation, template literal type inference, compile-time validation
- satisfies + as const: validate constraints while preserving literal types; maximum inference with type safety
- Performance: skipLibCheck for faster builds, incremental with .tsbuildinfo, project references with composite for monorepos
- Slow type checking fixes: replace intersections with interfaces, split large unions (>100 members), break circular generics
- Module resolution: match moduleResolution to bundler, verify baseUrl/paths alignment, TS paths are compile-time only
- Monorepos: Turborepo for simple (<20 packages), Nx for complex; use project references with composite:true and declarationMap
- Migration JS to TS: enable allowJs+checkJs, rename gradually, add types file-by-file, enable strict features incrementally
- Biome vs ESLint: Biome for speed and single-tool lint+format; ESLint for custom rules, Vue/Angular, type-aware linting
- Strict config: strict:true, noUncheckedIndexedAccess, exactOptionalPropertyTypes, ESM-first with type:"module"
- Code review: no implicit any (use unknown), minimal as assertions, explicit return types on public APIs, no circular deps
- Type testing: Vitest expectTypeOf for libraries and complex generics; validate AI-generated types with tests
