# Modern JavaScript Patterns

ES6+ features, functional programming, and best practices for clean, maintainable JavaScript.

- Destructuring: extract values from arrays and objects with defaults, renaming, and nested patterns
- Spread/rest: expand iterables into arrays/objects (...arr), collect remaining arguments (...args) in function signatures
- Arrow functions: concise syntax with lexical this binding; ideal for callbacks, not for methods needing their own this
- Template literals: multi-line strings, expression interpolation, tagged templates for DSLs
- Modules: named exports for utilities, default export for primary class/function, dynamic import() for code splitting
- Optional chaining (?.) safely accesses nested properties; nullish coalescing (??) provides defaults only for null/undefined
- Promises and async/await: replace callback pyramids with linear async flow; use Promise.all for parallel execution
- Iterators and generators: Symbol.iterator protocol, function* for lazy sequences, yield for on-demand computation
- Map/Set: Map for key-value with any key type, Set for unique values, WeakMap/WeakSet for garbage-collectible references
- Proxy/Reflect: intercept object operations for validation, logging, or reactive systems; foundation for Vue 3 reactivity
- Array methods pipeline: filter().map().reduce() for data transformation; prefer immutable operations over mutation
