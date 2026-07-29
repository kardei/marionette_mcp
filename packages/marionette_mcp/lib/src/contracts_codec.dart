// @marionette-codec-boundary: explicit JSON/VM/MCP codec boundary
part of marionette_contracts;

/// Versioned machine-readable contracts shared by MCP and CLI consumers.
const int contractSchemaVersion = 1;
const int contractProtocolVersion = 1;

/// A payload could not be decoded without inventing or dropping evidence.
class ContractFormatException implements Exception {
  const ContractFormatException(this.message, {this.path});

  final String message;
  final String? path;

  @override
  String toString() {
    final location = path == null ? '' : ' at $path';
    return 'ContractFormatException$location: $message';
  }
}

/// The finite severity vocabulary used by structured log contracts.
enum LogSeverity {
  debug('debug'),
  info('info'),
  warning('warning'),
  error('error'),
  critical('critical'),
  fatal('fatal');

  const LogSeverity(this.value);

  final String value;

  /// Converts a known legacy/text severity to the typed contract value.
  static LogSeverity fromLegacy(String value) {
    final normalized = value.trim().toLowerCase();
    for (final severity in values) {
      if (severity.value == normalized) return severity;
    }
    if (normalized == 'warn') return warning;
    throw ContractFormatException(
      'unsupported log severity "$value"',
      path: 'severity',
    );
  }

  /// Decodes the JSON scalar used by the wire contract.
  static LogSeverity fromJson(Object? value) {
    if (value is! String) {
      throw const ContractFormatException(
        'severity must be a string',
        path: 'severity',
      );
    }
    return fromLegacy(value);
  }
}

/// Machine-readable failure returned when an MCP/CLI payload is invalid.
class ContractFailure {
  const ContractFailure({
    required this.operation,
    required this.message,
    this.path,
  });

  factory ContractFailure.fromException(
    String operation,
    ContractFormatException error,
  ) {
    return ContractFailure(
      operation: operation,
      message: error.message,
      path: error.path,
    );
  }

  final String operation;
  final String message;
  final String? path;

  Map<String, dynamic> toJson() => {
        'schemaVersion': contractSchemaVersion,
        'protocolVersion': contractProtocolVersion,
        'success': false,
        'code': 'invalid_payload',
        'operation': operation,
        'message': message,
        if (path != null) 'path': path,
      };
}

Map<String, dynamic> _asJsonMap(Object? value, String path) {
  if (value is! Map) _invalid(path, 'must be an object');
  try {
    return Map<String, dynamic>.from(value);
  } on TypeError {
    _invalid(path, 'must have string keys');
  }
}

String _requiredString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! String) _invalid(key, 'must be a string');
  return value;
}

String? _optionalString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value == null) return null;
  if (value is! String) _invalid(key, 'must be a string or null');
  return value;
}

bool _requiredBool(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! bool) _invalid(key, 'must be a boolean');
  return value;
}

bool? _optionalBool(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value == null) return null;
  if (value is! bool) _invalid(key, 'must be a boolean or null');
  return value;
}

int _requiredInt(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! int) _invalid(key, 'must be an integer');
  return value;
}

int? _optionalInt(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value == null) return null;
  if (value is! int) _invalid(key, 'must be an integer or null');
  return value;
}

double _requiredNumber(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! num || !value.isFinite) {
    _invalid(key, 'must be a finite number');
  }
  return value.toDouble();
}

DateTime _requiredTime(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! String) _invalid(key, 'must be an ISO-8601 string');
  final parsed = DateTime.tryParse(value);
  if (parsed == null) _invalid(key, 'must be a valid ISO-8601 timestamp');
  return parsed.toUtc();
}

DateTime? _optionalTime(Map<String, dynamic> json, String key) {
  if (!json.containsKey(key) || json[key] == null) return null;
  return _requiredTime(json, key);
}

void _validateVersions(Map<String, dynamic> json) {
  final schema = json['schemaVersion'];
  if (schema != null && schema != contractSchemaVersion) {
    _invalid('schemaVersion', 'unsupported contract schema version');
  }
  final protocol = json['protocolVersion'];
  if (protocol != null && protocol != contractProtocolVersion) {
    _invalid('protocolVersion', 'unsupported contract protocol version');
  }
}

Never _invalid(String path, String message) {
  throw ContractFormatException(message, path: path);
}
