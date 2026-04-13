# Frontend Development Guidelines

Opinionated React + TypeScript standards: Suspense-first, feature-based architecture, strict types, performance-safe defaults.

- Suspense is the default: use useSuspenseQuery for data fetching; no isLoading conditionals, no manual spinners
- Lazy load anything heavy: routes, feature entry components, data grids, charts, editors, large modals
- Feature-based organization: domain logic in features/, reusable primitives in components/, no cross-feature coupling
- TypeScript is strict: no any, explicit return types, import type always, types are first-class design artifacts
- Component structure order: types/props, hooks, derived values (useMemo), handlers (useCallback), render, default export
- Data fetching: useSuspenseQuery with cache-first strategy and typed responses; API layer isolated per feature
- Routing: TanStack Router with folder-based routing, lazy loaded route components, breadcrumb metadata via loaders
- Styling: MUI v7 with inline sx for small components (<100 lines), separate .styles.ts for larger ones
- Performance defaults: useMemo for expensive derivations, useCallback for passed handlers, React.memo for heavy pure components, debounce search 300-500ms
- Anti-patterns to reject: early loading returns, feature logic in components/, inline API calls, untyped responses, prop drilling instead of hooks
