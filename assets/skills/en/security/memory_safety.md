# Memory Safety Patterns

Cross-language memory-safe programming: RAII, ownership, smart pointers, and resource management.

- RAII (Resource Acquisition Is Initialization): tie resource lifetime to scope; destructors release automatically
- Rust ownership: single owner, move semantics by default, borrow checker enforces lifetimes at compile time
- C++ smart pointers: use unique_ptr for sole ownership, shared_ptr for shared ownership, weak_ptr to break cycles
- Never use raw new/delete in modern C++; prefer make_unique and make_shared for exception safety
- Use-after-free prevention: nullify pointers after free, prefer RAII wrappers, use sanitizers (ASan, MSan) in testing
- Buffer overflow: use bounds-checked containers (std::vector, Rust slices), avoid raw pointer arithmetic
- Double-free: RAII eliminates this class; in C, set pointer to NULL after free and check before operations
- Rust lifetimes: annotate when compiler cannot infer; prefer references over raw pointers, use Arc for thread-safe sharing
- Memory leak detection: use Valgrind, LeakSanitizer, or Instruments; ensure all resources have clear ownership
- Resource management beyond memory: apply RAII to files, sockets, locks, and database connections
