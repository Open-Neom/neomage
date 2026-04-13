# JavaScript Mastery

Core JavaScript concepts: primitives, closures, prototypes, async patterns, and functional programming.

- 7 primitives (string, number, bigint, boolean, undefined, null, symbol); primitives are immutable and passed by value
- Type coercion: "5"+3="53", "5"-3=2; 8 falsy values (false, 0, -0, 0n, "", null, undefined, NaN); always use ===
- Closures: function + lexical scope; use for data privacy, factories, partial application, memoization
- var is function-scoped and hoisted; let/const are block-scoped with TDZ; prefer const, then let, never var
- this: depends on call site -- object method (the object), arrow function (lexical), explicit (call/apply/bind)
- Event loop order: synchronous call stack, then microtasks (Promises, queueMicrotask), then macrotasks (setTimeout, I/O)
- Promises: all/allSettled/race/any combinators; async/await for readable sequential flow; always handle errors with try/catch
- Functional: pure functions (same input=same output), higher-order functions (map/filter/reduce), currying, composition (pipe/compose)
- Prototypal inheritance: Object.create for delegation, ES6 classes as syntactic sugar; prefer composition over inheritance
- Modern ES6+: destructuring, spread/rest, modules (import/export), optional chaining (?.), nullish coalescing (?? checks only null/undefined)
