# Flutter State Management — Reactive Patterns

## Purpose

Choose and implement the right state management approach for Flutter applications. Focus on Sint (S.I.N.T.) as the primary framework.

## Sint Framework Pattern

### Controller
```dart
class MyController extends SintController {
  final items = <Item>[].obs;        // RxList — reactive
  final isLoading = false.obs;       // RxBool — reactive
  final selected = Rxn<Item>();      // Nullable reactive

  @override
  void onInit() {
    super.onInit();
    ever(items, (_) => _recalculate()); // Worker: reacts to changes
    fetchItems();
  }

  Future<void> fetchItems() async {
    isLoading.value = true;
    items.value = await _repository.getAll();
    isLoading.value = false;
  }

  @override
  void onClose() {
    // Cleanup — workers auto-dispose
    super.onClose();
  }
}
```

### Widget Binding
```dart
// Obx — automatic reactive rebuild
Obx(() => items.isEmpty
    ? const EmptyState()
    : ListView(children: ctrl.items.map(ItemTile.new).toList()));

// SintBuilder — with init and lifecycle
SintBuilder<MyController>(
  init: MyController(),
  builder: (ctrl) => Obx(() => Text('${ctrl.items.length} items')),
);
```

### Dependency Injection
```dart
// Register
Sint.put(AuthController(), permanent: true);
Sint.lazyPut(() => DataService());

// Retrieve
final auth = Sint.find<AuthController>();
```

## State Categories

| Type | Scope | Example | Pattern |
|------|-------|---------|---------|
| Ephemeral | Widget | Animation, form input | setState |
| App | Global | Auth, theme, locale | Sint permanent controller |
| Feature | Screen/flow | Chat messages, cart | Sint lazy controller |
| Server | Remote | API data | Controller + service |

## Best Practices

- One controller per feature, not per screen
- Use `.obs` for reactive state, not raw variables
- Prefer `Obx` over `SintBuilder` for simple reactivity
- Keep business logic in controllers, not widgets
- Use `permanent: true` only for truly app-lifetime services
