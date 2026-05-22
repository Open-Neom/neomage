import 'package:flutter_test/flutter_test.dart';
import 'package:neomage/data/tools/js_sandbox_tool.dart';

void main() {
  // Ensure Flutter binds are initialized for plugins (like flutter_js)
  TestWidgetsFlutterBinding.ensureInitialized();

  group('JsSandboxTool', () {
    late JsSandboxTool tool;

    setUp(() {
      tool = JsSandboxTool();
    });

    test('metadata checks', () {
      expect(tool.name, 'js_sandbox');
      expect(tool.description, contains('JavaScript'));
      expect(tool.isReadOnly, isTrue);
      expect(tool.isConcurrencySafe, isTrue);
      expect(tool.inputSchema['properties'], contains('code'));
    });

    test('validateInput works', () {
      final valid = tool.validateInput({'code': '2 + 2'});
      expect(valid.isValid, isTrue);
    });

    test('execute basic math', () async {
      final result = await tool.execute({'code': '2 + 2'});
      expect(result.isError, isFalse);
      expect(result.content, equals('4'));
    });

    test('execute custom function', () async {
      final result = await tool.execute({
        'code': 'function multiply(a, b) { return a * b; } multiply(5, 6);'
      });
      expect(result.isError, isFalse);
      expect(result.content, equals('30'));
    });

    test('handling javascript syntax/runtime errors', () async {
      final result = await tool.execute({
        'code': 'nonExistentFunction();'
      });
      expect(result.isError, isTrue);
      expect(result.content, contains('Error'));
    });

    test('empty code returns error', () async {
      final result = await tool.execute({'code': '  '});
      expect(result.isError, isTrue);
      expect(result.content, contains('No se proporcionó código'));
    });
  });
}
