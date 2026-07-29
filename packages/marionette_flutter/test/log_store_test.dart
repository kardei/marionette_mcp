import 'package:flutter_test/flutter_test.dart';
import 'package:marionette_flutter/marionette_flutter.dart';

void main() {
  test('LogStore assigns monotonic sequences and returns deltas', () {
    final store = LogStore();
    store.addEntry(
      LogEntry(
        timestamp: DateTime.utc(2026, 7, 29, 12),
        severity: LogSeverity.error,
        source: 'test',
        message: 'failed',
        error: StateError('bad state'),
        stack: StackTrace.current,
      ),
    );
    store.add('legacy');

    final snapshot = store.getLogSnapshot(afterSequence: 1);
    expect(snapshot['cursor'], 2);
    expect(snapshot['count'], 1);
    expect((snapshot['entries'] as List).single['sequence'], 2);
    expect((snapshot['entries'] as List).single['severity'], 'info');
    expect(store.getLogs(), ['failed', 'legacy']);
  });

  test('structured entries without timestamps fail instead of inventing one',
      () {
    final store = LogStore();

    expect(
      () => store.addEntry(const LogEntry(message: 'missing timestamp')),
      throwsA(isA<LogEntryFormatException>()),
    );
  });

  test('structured JSON emits typed severity values and rejects unknown ones',
      () {
    final entry = LogEntry(
      timestamp: DateTime.utc(2026, 7, 29, 12),
      severity: LogSeverity.critical,
      source: 'test',
      message: 'critical event',
    );
    final json = entry.toJson(sequence: 1);
    expect(json['severity'], 'critical');
    expect(LogEntry.fromJson(json).severity, LogSeverity.critical);
    expect(
      () => LogEntry.fromJson({...json, 'severity': 'unknown'}),
      throwsA(isA<LogEntryFormatException>()),
    );
  });

  test('legacy severity conversion is explicit and strict', () {
    expect(
      LogEntry.fromLegacy(message: 'legacy', severity: 'WARN').severity,
      LogSeverity.warning,
    );
    expect(
      () => LogEntry.fromLegacy(message: 'legacy', severity: 'notice'),
      throwsA(isA<LogEntryFormatException>()),
    );
  });
}
