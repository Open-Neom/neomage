import 'dart:convert';

/// Represents a Model Context Protocol (MCP) Tool definition.
class McpTool {
  final String name;
  final String description;
  final Map<String, dynamic> inputSchema;

  const McpTool({
    required this.name,
    required this.description,
    required this.inputSchema,
  });

  factory McpTool.fromJson(Map<String, dynamic> json) {
    return McpTool(
      name: json['name'] as String? ?? '',
      description: json['description'] as String? ?? '',
      inputSchema: (json['inputSchema'] as Map<String, dynamic>?) ?? {},
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'description': description,
        'inputSchema': inputSchema,
      };
}

/// Represents an MCP Resource definition.
class McpResource {
  final String uri;
  final String name;
  final String? description;
  final String? mimeType;

  const McpResource({
    required this.uri,
    required this.name,
    this.description,
    this.mimeType,
  });

  factory McpResource.fromJson(Map<String, dynamic> json) {
    return McpResource(
      uri: json['uri'] as String? ?? '',
      name: json['name'] as String? ?? '',
      description: json['description'] as String?,
      mimeType: json['mimeType'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'uri': uri,
        'name': name,
        if (description != null) 'description': description,
        if (mimeType != null) 'mimeType': mimeType,
      };
}

/// Represents a request sent to or received from an MCP Server (JSON-RPC 2.0).
class McpRequest {
  final String jsonrpc;
  final String method;
  final Map<String, dynamic> params;
  final dynamic id;

  const McpRequest({
    this.jsonrpc = '2.0',
    required this.method,
    this.params = const {},
    this.id,
  });

  Map<String, dynamic> toJson() => {
        'jsonrpc': jsonrpc,
        'method': method,
        if (params.isNotEmpty) 'params': params,
        if (id != null) 'id': id,
      };

  String toJsonString() => jsonEncode(toJson());
}

/// Represents a response received from an MCP Server.
class McpResponse {
  final String jsonrpc;
  final dynamic id;
  final dynamic result;
  final McpError? error;

  const McpResponse({
    this.jsonrpc = '2.0',
    required this.id,
    this.result,
    this.error,
  });

  factory McpResponse.fromJson(Map<String, dynamic> json) {
    return McpResponse(
      jsonrpc: json['jsonrpc'] as String? ?? '2.0',
      id: json['id'],
      result: json['result'],
      error: json['error'] != null
          ? McpError.fromJson(json['error'] as Map<String, dynamic>)
          : null,
    );
  }

  bool get isError => error != null;
}

/// Represents a standard JSON-RPC 2.0 Error.
class McpError {
  final int code;
  final String message;
  final dynamic data;

  const McpError({
    required this.code,
    required this.message,
    this.data,
  });

  factory McpError.fromJson(Map<String, dynamic> json) {
    return McpError(
      code: json['code'] as int? ?? -32603,
      message: json['message'] as String? ?? 'Internal Error',
      data: json['data'],
    );
  }

  Map<String, dynamic> toJson() => {
        'code': code,
        'message': message,
        if (data != null) 'data': data,
      };

  @override
  String toString() => 'MCP Error ($code): $message';
}
