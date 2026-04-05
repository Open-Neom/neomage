# Clean Code

Principles for writing readable, maintainable code that other developers can understand and enhance.

- Use intention-revealing names: `elapsedTimeInDays` not `d`; class nouns, method verbs
- Functions should do one thing, stay under 20 lines, and take 0-2 arguments
- Don't comment bad code -- rewrite it; express intent through code, not comments
- Follow the Newspaper Metaphor: high-level concepts at top, details at bottom
- Hide implementation behind abstractions; obey the Law of Demeter (no train wrecks)
- Use exceptions instead of return codes; never return or pass null
- Classes should have a single responsibility and read as a top-down narrative
- Code smells to watch: rigidity, fragility, immobility, needless complexity/repetition
- Tests follow FIRST principles: Fast, Independent, Repeatable, Self-Validating, Timely
