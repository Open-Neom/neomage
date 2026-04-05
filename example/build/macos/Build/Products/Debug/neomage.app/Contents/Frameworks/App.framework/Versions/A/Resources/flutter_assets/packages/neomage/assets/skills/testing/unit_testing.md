# Unit Testing — Systematic Test Generation

## Purpose

Write comprehensive, maintainable unit tests that catch regressions and document behavior.

## Test Structure (AAA)

```
Arrange → Act → Assert
```

- **Arrange**: Set up test data, mocks, and dependencies
- **Act**: Execute the function/method under test
- **Assert**: Verify the outcome matches expectations

## What to Test

### Coverage Targets
- Happy path (expected inputs → expected outputs)
- Edge cases (empty, null, boundary values, max/min)
- Error handling (invalid inputs, network failures, exceptions)
- State transitions (before/after side effects)

### Flutter/Dart Specific
```dart
// Widget test
testWidgets('shows loading indicator', (tester) async {
  await tester.pumpWidget(const MyApp());
  expect(find.byType(CircularProgressIndicator), findsOneWidget);
});

// Unit test
test('calculates total correctly', () {
  final cart = Cart()..addItem(Item(price: 10))..addItem(Item(price: 20));
  expect(cart.total, equals(30));
});

// Async test
test('fetches data successfully', () async {
  final service = MyService(mockClient);
  when(mockClient.get(any)).thenAnswer((_) async => Response('{}', 200));
  final result = await service.fetchData();
  expect(result, isNotNull);
});
```

## Best Practices

- One assertion per test (when practical)
- Descriptive test names: `should_returnEmpty_when_noItemsExist`
- Test behavior, not implementation details
- Use factories/builders for test data
- Mock external dependencies, not internal logic
- Run tests in CI on every commit

## Anti-Patterns

- Testing private methods directly
- Tests that depend on execution order
- Flaky tests (timing-dependent, network-dependent)
- Too many mocks (testing the mocks, not the code)
