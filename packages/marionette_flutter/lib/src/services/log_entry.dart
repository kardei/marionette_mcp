// @marionette-codec-boundary: explicit JSON/VM/MCP codec boundary

/// Thrown when a structured log entry does not contain required evidence.
class LogEntryFormatException implements Exception {
  const LogEntryFormatException(this.message, {this.path});

  final String message;
  final String? path;

  @override
  String toString() {
    final location = path == null ? '' : ' at $path';
    return 'LogEntryFormatException$location: $message';
  }
}

/// The finite severity vocabulary used by Flutter structured logs.
enum LogSeverity {
  debug('debug'),
  info('info'),
  warning('warning'),
  error('error'),
  critical('critical'),
  fatal('fatal');

  const LogSeverity(this.value);

  final String value;

  /// Explicitly converts a known legacy/text severity.
  static LogSeverity fromLegacy(String value) {
    final normalized = value.trim().toLowerCase();
    for (final severity in values) {
      if (severity.value == normalized) return severity;
    }
    if (normalized == 'warn') return warning;
    throw LogEntryFormatException(
      'unsupported log severity "$value"',
      path: 'severity',
    );
  }

  /// Decodes the JSON scalar used by the structured log codec.
  static LogSeverity fromJson(Object? value) {
    if (value is! String) {
      throw const LogEntryFormatException(
        'severity must be a string',
        path: 'severity',
      );
    }
    return fromLegacy(value);
  }
}

/// A structured log event accepted by Marionette's log store.
class LogEntry {
  const LogEntry({
    required this.message,
    this.timestamp,
    this.severity = LogSeverity.info,
    this.source = 'legacy',
    this.error,
    this.stack,
  });

  const LogEntry.legacy(String message)
      : this(message: message, severity: LogSeverity.info, source: 'legacy');

  /// Creates a typed entry from the existing string-based logging vocabulary.
  factory LogEntry.fromLegacy({
    required String message,
    DateTime? timestamp,
    String severity = 'info',
    String source = 'legacy',
    Object? error,
    StackTrace? stack,
  }) {
    return LogEntry(
      message: message,
      timestamp: timestamp,
      severity: LogSeverity.fromLegacy(severity),
      source: source,
      error: error,
      stack: stack,
    );
  }

  /// Decodes a structured log entry without supplying fallback evidence.
  factory LogEntry.fromJson(Map<String, dynamic> json) {
    final sequence = json['sequence'];
    if (sequence is! int || sequence < 0) {
      throw const LogEntryFormatException(
        'sequence must be a non-negative integer',
        path: 'sequence',
      );
    }
    final timestamp = json['timestamp'];
    if (timestamp is! String) {
      throw const LogEntryFormatException(
        'timestamp must be an ISO-8601 string',
        path: 'timestamp',
      );
    }
    final parsedTimestamp = DateTime.tryParse(timestamp);
    if (parsedTimestamp == null) {
      throw const LogEntryFormatException(
        'timestamp must be a valid ISO-8601 timestamp',
        path: 'timestamp',
      );
    }
    return LogEntry(
      timestamp: parsedTimestamp.toUtc(),
      severity: LogSeverity.fromJson(json['severity']),
      source: _requiredString(json, 'source'),
      message: _requiredString(json, 'message'),
      error: _optionalString(json, 'error'),
      stack: _optionalStack(json, 'stack'),
    );
  }

  final DateTime? timestamp;
  final LogSeverity severity;
  final String source;
  final String message;
  final Object? error;
  final StackTrace? stack;

  LogEntry copyWith({required DateTime timestamp}) => LogEntry(
        message: message,
        timestamp: timestamp,
        severity: severity,
        source: source,
        error: error,
        stack: stack,
      );

  Map<String, dynamic> toJson({required int sequence}) => {
        'sequence': sequence,
        'timestamp': _requiredTimestamp().toUtc().toIso8601String(),
        'severity': severity.value,
        'source': source,
        'message': message,
        'error': error?.toString(),
        'stack': stack?.toString(),
      };

  DateTime _requiredTimestamp() {
    final value = timestamp;
    if (value == null) {
      throw const LogEntryFormatException(
        'structured log timestamp is required',
      );
    }
    return value;
  }
}

String _requiredString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! String) {
    throw LogEntryFormatException('$key must be a string', path: key);
  }
  return value;
}

String? _optionalString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value == null) return null;
  if (value is! String) {
    throw LogEntryFormatException('$key must be a string or null', path: key);
  }
  return value;
}

StackTrace? _optionalStack(Map<String, dynamic> json, String key) {
  final value = _optionalString(json, key);
  return value == null ? null : StackTrace.fromString(value);
}
// @marionette-codec-boundary: explicit JSON/VM/MCP codec boundary
