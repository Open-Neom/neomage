# TypeScript Advanced Types

Generics, conditional types, mapped types, template literals, and utility types for type-safe applications.

- Generics: parameterize types for reusable functions, classes, and interfaces; constrain with extends for bounds
- Conditional types: T extends U ? X : Y for type-level branching; use infer to extract types within conditions
- Mapped types: transform object types with {[K in keyof T]: NewType}; combine with modifiers (readonly, optional)
- Template literal types: build string types from unions; useful for event names, route paths, CSS properties
- Utility types: Partial, Required, Pick, Omit, Record, Exclude, Extract, ReturnType, Parameters, Awaited
- Discriminated unions: shared literal field (kind/type) enables exhaustive switch/case with never for completeness checks
- Branded/nominal types: type Brand<K,T> = K & {__brand:T} prevents mixing primitives (UserId vs OrderId)
- satisfies operator: validate a value matches a type while preserving the narrower inferred type
- const assertions (as const): infer literal types and readonly tuples from values; enables type-safe configuration objects
- DeepReadonly/DeepPartial: recursive type utilities for immutable or optional deep structures; limit recursion depth to avoid compiler errors
