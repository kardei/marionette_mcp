// @marionette-codec-boundary: explicit JSON/VM/MCP codec boundary
part of marionette_contracts;

/// A structured application log entry.
class StructuredLogEntry {
  StructuredLogEntry({
    required this.sequence,
    required this.timestamp,
    required this.severity,
    required this.source,
    required this.message,
    this.error,
    this.stack,
  });

  /// Creates a typed entry from the existing string-based log vocabulary.
  factory StructuredLogEntry.fromLegacy({
    required int sequence,
    required DateTime timestamp,
    required String severity,
    required String source,
    required String message,
    String? error,
    String? stack,
  }) {
    return StructuredLogEntry(
      sequence: sequence,
      timestamp: timestamp,
      severity: LogSeverity.fromLegacy(severity),
      source: source,
      message: message,
      error: error,
      stack: stack,
    );
  }

  factory StructuredLogEntry.fromJson(Map<String, dynamic> json) {
    final sequence = _requiredInt(json, 'sequence');
    if (sequence < 0) _invalid('sequence', 'must be non-negative');
    return StructuredLogEntry(
      sequence: sequence,
      timestamp: _requiredTime(json, 'timestamp'),
      severity: LogSeverity.fromJson(json['severity']),
      source: _requiredString(json, 'source'),
      message: _requiredString(json, 'message'),
      error: _optionalString(json, 'error'),
      stack: _optionalString(json, 'stack'),
    );
  }

  final int sequence;
  final DateTime timestamp;
  final LogSeverity severity;
  final String source;
  final String message;
  final String? error;
  final String? stack;

  Map<String, dynamic> toJson() => {
        'sequence': sequence,
        'timestamp': timestamp.toUtc().toIso8601String(),
        'severity': severity.value,
        'source': source,
        'message': message,
        'error': error,
        'stack': stack,
      };
}

/// A log delta together with its cursor.
class LogSnapshot {
  LogSnapshot({
    required List<StructuredLogEntry> entries,
    required this.cursor,
    this.afterSequence,
    List<String>? legacyLogs,
  })  : entries = List.unmodifiable(entries),
        legacyLogs = List.unmodifiable(
          legacyLogs ?? [for (final entry in entries) entry.message],
        );

  factory LogSnapshot.fromJson(Map<String, dynamic> json) {
    _validateVersions(json);
    final hasEntries = json.containsKey('entries');
    final hasLogs = json.containsKey('logs');
    if (!hasEntries && !hasLogs) {
      _invalid('entries', 'or logs is required');
    }

    final entries = <StructuredLogEntry>[];
    if (hasEntries) {
      final rawEntries = json['entries'];
      if (rawEntries is! List) _invalid('entries', 'must be a list');
      for (var i = 0; i < rawEntries.length; i++) {
        final raw = rawEntries[i];
        if (raw is! Map) _invalid('entries[$i]', 'must be an object');
        entries.add(StructuredLogEntry.fromJson(
          _asJsonMap(raw, 'entries[$i]'),
        ));
      }
    }

    final legacyLogs = <String>[];
    if (hasLogs) {
      final rawLogs = json['logs'];
      if (rawLogs is! List) _invalid('logs', 'must be a list');
      for (var i = 0; i < rawLogs.length; i++) {
        final raw = rawLogs[i];
        if (raw is! String) _invalid('logs[$i]', 'must be a string');
        legacyLogs.add(raw);
      }
      if (hasEntries && legacyLogs.length != entries.length) {
        _invalid('logs', 'must contain one legacy message per entry');
      }
    }

    final cursor = hasEntries
        ? _requiredInt(json, 'cursor')
        : (_optionalInt(json, 'cursor') ?? 0);
    if (cursor < 0) _invalid('cursor', 'must be non-negative');
    if (entries.any((entry) => entry.sequence > cursor)) {
      _invalid('cursor', 'must be at least the largest entry sequence');
    }
    final afterSequence = _optionalInt(json, 'afterSequence');
    final count = _optionalInt(json, 'count');
    final expectedCount = hasEntries ? entries.length : legacyLogs.length;
    if (count != null && count != expectedCount) {
      _invalid('count', 'does not match the payload length');
    }
    return LogSnapshot(
      entries: entries,
      cursor: cursor,
      afterSequence: afterSequence,
      legacyLogs: legacyLogs,
    );
  }

  final List<StructuredLogEntry> entries;
  final List<String> legacyLogs;
  final int cursor;
  final int? afterSequence;

  int get count => entries.isNotEmpty ? entries.length : legacyLogs.length;

  Map<String, dynamic> toJson() => {
        'schemaVersion': contractSchemaVersion,
        'protocolVersion': contractProtocolVersion,
        'entries': [for (final entry in entries) entry.toJson()],
        'logs': legacyLogs,
        'count': count,
        'cursor': cursor,
        if (afterSequence != null) 'afterSequence': afterSequence,
      };
}
