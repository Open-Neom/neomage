// ToolSearch tool — port of neom_claw/src/tools/ToolSearchTool.
// Finds deferred tools by name or keyword search.

import 'tool.dart';
import 'tool_registry.dart';

/// ToolSearch tool — discovers and loads deferred tools on demand.
class ToolSearchTool extends Tool {
  final ToolRegistry registry;

  ToolSearchTool({required this.registry});

  @override
  String get name => 'ToolSearch';

  @override
  String get description =>
      'Fetches full schema definitions for deferred tools so they can be '
      'called. Takes a query string and returns matched tools\' complete '
      'definitions.';

  @override
  bool get isReadOnly => true;

  @override
  bool get isConcurrencySafe => true;

  // ToolSearch itself must never be deferred
  @override
  bool get shouldDefer => false;

  @override
  bool get alwaysLoad => true;

  @override
  Map<String, dynamic> get inputSchema => {
    'type': 'object',
    'properties': {
      'query': {
        'type': 'string',
        'description':
            'Query to find tools. Use "select:<tool_name>" for direct '
            'selection, or keywords to search.',
      },
      'max_results': {
        'type': 'number',
        'description': 'Maximum number of results (default: 5)',
      },
    },
    'required': ['query'],
  };

  @override
  Future<ToolResult> execute(Map<String, dynamic> input) async {
    final query = input['query'] as String?;
    final maxResults = (input['max_results'] as num?)?.toInt() ?? 5;

    if (query == null || query.isEmpty) {
      return ToolResult.error('Missing required parameter: query');
    }

    final deferredTools = registry.all
        .where((t) => _isDeferredTool(t))
        .toList();

    // Direct selection: "select:ToolName" or "select:A,B,C"
    if (query.startsWith('select:')) {
      return _handleDirectSelection(query.substring(7), deferredTools);
    }

    // Keyword search
    return _handleKeywordSearch(query, deferredTools, maxResults);
  }

  ToolResult _handleDirectSelection(String selector, List<Tool> deferred) {
    final names = selector.split(',').map((s) => s.trim()).toList();
    final matched = <Tool>[];
    final missing = <String>[];

    for (final name in names) {
      // Search both deferred and full registry
      final tool = deferred.firstWhere(
        (t) => t.name == name,
        orElse: () => registry.get(name) ?? _nullTool,
      );
      if (tool != _nullTool) {
        matched.add(tool);
      } else {
        missing.add(name);
      }
    }

    if (matched.isEmpty) {
      return ToolResult.error('No tools found matching: ${names.join(", ")}');
    }

    final buffer = StringBuffer();
    buffer.writeln('<functions>');
    for (final tool in matched) {
      buffer.writeln(_formatToolDefinition(tool));
    }
    buffer.writeln('</functions>');

    if (missing.isNotEmpty) {
      buffer.writeln('Note: Not found: ${missing.join(", ")}');
    }

    return ToolResult.success(
      buffer.toString(),
      metadata: {
        'matches': matched.map((t) => t.name).toList(),
        'total_deferred_tools': deferred.length,
      },
    );
  }

  ToolResult _handleKeywordSearch(
    String query,
    List<Tool> deferred,
    int maxResults,
  ) {
    final terms = _parseQuery(query);
    final requiredTerms = terms
        .where((t) => t.startsWith('+'))
        .map((t) => t.substring(1))
        .toList();
    final optionalTerms = terms.where((t) => !t.startsWith('+')).toList();

    final scored = <_ScoredTool>[];

    for (final tool in deferred) {
      final parts = _parseToolName(tool.name);
      final desc = tool.description.toLowerCase();

      // Filter: must match all required terms
      if (requiredTerms.isNotEmpty) {
        final nameAndDesc = '${tool.name.toLowerCase()} $desc';
        final allRequired = requiredTerms.every(
          (r) => nameAndDesc.contains(r.toLowerCase()),
        );
        if (!allRequired) continue;
      }

      var score = 0;
      for (final term in [...requiredTerms, ...optionalTerms]) {
        final t = term.toLowerCase();
        // Exact part match (highest weight)
        if (parts.any((p) => p == t)) {
          score += 12;
        }
        // Substring within parts
        else if (parts.any((p) => p.contains(t))) {
          score += 6;
        }
        // Full name match
        else if (tool.name.toLowerCase().contains(t)) {
          score += 4;
        }
        // Description match
        else if (desc.contains(t)) {
          score += 2;
        }
      }

      if (score > 0) {
        scored.add(_ScoredTool(tool, score));
      }
    }

    if (scored.isEmpty) {
      return ToolResult.success(
        'No deferred tools found matching "$query". '
        'Total deferred tools available: ${deferred.length}',
      );
    }

    scored.sort((a, b) => b.score.compareTo(a.score));
    final results = scored.take(maxResults).toList();

    final buffer = StringBuffer();
    buffer.writeln('<functions>');
    for (final s in results) {
      buffer.writeln(_formatToolDefinition(s.tool));
    }
    buffer.writeln('</functions>');

    return ToolResult.success(
      buffer.toString(),
      metadata: {
        'matches': results.map((s) => s.tool.name).toList(),
        'query': query,
        'total_deferred_tools': deferred.length,
      },
    );
  }

  bool _isDeferredTool(Tool tool) {
    if (tool.alwaysLoad) return false;
    if (tool.name == 'ToolSearch') return false;
    if (tool.isMcp) return true;
    return tool.shouldDefer;
  }

  List<String> _parseToolName(String name) {
    // MCP format: mcp__server__action
    if (name.startsWith('mcp__')) {
      return name.split('__').skip(1).toList();
    }
    // CamelCase split
    return name
        .replaceAllMapped(
          RegExp(r'([a-z])([A-Z])'),
          (m) => '${m.group(1)} ${m.group(2)}',
        )
        .toLowerCase()
        .split(RegExp(r'[\s_]+'));
  }

  List<String> _parseQuery(String query) {
    return query.split(RegExp(r'\s+')).where((s) => s.isNotEmpty).toList();
  }

  String _formatToolDefinition(Tool tool) {
    return '<function>{"name": "${tool.name}", '
        '"description": "${_escapeJson(tool.description)}", '
        '"parameters": ${_mapToJson(tool.inputSchema)}}'
        '</function>';
  }

  String _escapeJson(String s) =>
      s.replaceAll('"', r'\"').replaceAll('\n', r'\n');

  String _mapToJson(Map<String, dynamic> map) {
    // Simple JSON serialization for schema
    final entries = map.entries.map((e) {
      final value = e.value;
      if (value is String) return '"${e.key}": "${_escapeJson(value)}"';
      if (value is bool) return '"${e.key}": $value';
      if (value is num) return '"${e.key}": $value';
      if (value is Map) return '"${e.key}": ${_mapToJson(value.cast())}';
      if (value is List) return '"${e.key}": ${_listToJson(value)}';
      return '"${e.key}": null';
    });
    return '{${entries.join(", ")}}';
  }

  String _listToJson(List list) {
    final items = list.map((v) {
      if (v is String) return '"${_escapeJson(v)}"';
      if (v is Map) return _mapToJson(v.cast());
      return '$v';
    });
    return '[${items.join(", ")}]';
  }

  static final _nullTool = _NullTool();
}

class _ScoredTool {
  final Tool tool;
  final int score;
  _ScoredTool(this.tool, this.score);
}

class _NullTool extends Tool {
  @override
  String get name => '__null__';
  @override
  String get description => '';
  @override
  Map<String, dynamic> get inputSchema => {};
  @override
  Future<ToolResult> execute(Map<String, dynamic> input) async =>
      ToolResult.error('null tool');
}
