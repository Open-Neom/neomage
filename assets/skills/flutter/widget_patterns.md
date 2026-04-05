# Flutter Widget Patterns — Composable UI

## Purpose

Build maintainable, performant Flutter UIs using proven widget composition patterns.

## Core Patterns

### 1. Composition Over Inheritance
```dart
// GOOD: Compose with parameters
class ActionCard extends StatelessWidget {
  final Widget icon;
  final String title;
  final VoidCallback onTap;
  // ...
}

// BAD: Extend and override
class SpecialCard extends Card { /* fragile */ }
```

### 2. Builder Pattern for Complex Widgets
```dart
class DataTable extends StatelessWidget {
  final List<T> items;
  final Widget Function(T item) rowBuilder;
  final Widget Function()? emptyBuilder;
  final Widget Function()? loadingBuilder;
}
```

### 3. Slot Pattern
Expose named widget slots for customization:
```dart
class AppBar({
  Widget? leading,      // slot
  Widget? title,        // slot
  List<Widget>? actions, // slot
})
```

### 4. Smart + Dumb Split
- **Smart widgets**: Have controllers, handle state, make API calls
- **Dumb widgets**: Pure UI, receive data via constructor, emit events via callbacks

### 5. Const Constructors Everywhere
```dart
// 30% fewer rebuilds in practice
const MyWidget({super.key, required this.title});
```

## Performance Patterns

- Use `const` widgets to skip rebuild
- Extract subtrees that rebuild independently
- Use `RepaintBoundary` for complex animations
- Lazy-load heavy widgets with `Visibility`/`Offstage`
- Use `ListView.builder` instead of `ListView(children: [...])`

## Anti-Patterns

- God widgets (500+ lines with nested `setState`)
- Rebuilding entire trees for single value changes
- Passing data through 5+ levels of constructors (use DI instead)
- Mixing business logic in `build()` methods
