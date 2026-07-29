import 'dart:collection';

import 'package:marionette_flutter/src/binding/contract_versions.dart';
import 'package:marionette_flutter/src/services/log_entry.dart';

/// Stores collected logs in memory with a maximum capacity.
///
/// This class is used internally by [MarionetteBinding] to store logs
/// received from a [LogCollector].
class LogStore {
  final _logs = Queue<_StoredLogEntry>();
  int _nextSequence = 1;

  /// Maximum number of logs to store. Older logs are discarded when exceeded.
  static const maxLogs = 1000;

  /// Adds a log entry to the store.
  ///
  /// If the store is at capacity, the oldest log entry is removed.
  void add(String log) {
    addEntry(LogEntry(
      message: log,
      timestamp: DateTime.now(),
      severity: LogSeverity.info,
      source: 'legacy',
    ));
  }

  /// Adds a structured log entry and assigns its monotonic sequence.
  void addEntry(LogEntry entry) {
    _logs.add(
      _StoredLogEntry(
        sequence: _nextSequence++,
        entry: entry.copyWith(timestamp: _requiredTimestamp(entry)),
      ),
    );

    // Keep only the most recent logs
    if (_logs.length > maxLogs) {
      _logs.removeFirst();
    }
  }

  /// Returns all collected logs as a list of strings.
  List<String> getLogs() {
    return [for (final log in _logs) log.entry.message];
  }

  /// Returns structured log entries after [afterSequence], if supplied.
  List<Map<String, dynamic>> getStructuredLogs({int? afterSequence}) {
    return [
      for (final log in _logs)
        if (afterSequence == null || log.sequence > afterSequence)
          log.entry.toJson(sequence: log.sequence),
    ];
  }

  /// The latest assigned sequence, including entries evicted by the cap.
  int get cursor => _nextSequence - 1;

  /// Returns a read-only log delta and cursor for VM service codecs.
  Map<String, dynamic> getLogSnapshot({int? afterSequence}) {
    final entries = getStructuredLogs(afterSequence: afterSequence);
    return {
      'schemaVersion': marionetteContractSchemaVersion,
      'protocolVersion': marionetteContractProtocolVersion,
      'entries': entries,
      'logs': [
        for (final entry in entries) entry['message'],
      ],
      'count': entries.length,
      'cursor': cursor,
      if (afterSequence != null) 'afterSequence': afterSequence,
    };
  }

  /// Clears all collected logs.
  void clear() {
    _logs.clear();
  }

  /// Returns the number of collected logs.
  int get count => _logs.length;

  DateTime _requiredTimestamp(LogEntry entry) {
    final timestamp = entry.timestamp;
    if (timestamp == null) {
      throw const LogEntryFormatException(
        'structured log timestamp is required',
      );
    }
    return timestamp;
  }
}

class _StoredLogEntry {
  const _StoredLogEntry({required this.sequence, required this.entry});

  final int sequence;
  final LogEntry entry;
}
// @marionette-codec-boundary: explicit JSON/VM/MCP codec boundary
