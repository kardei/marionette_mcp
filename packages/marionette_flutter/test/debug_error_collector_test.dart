import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marionette_flutter/marionette_flutter.dart';

void main() {
  late FlutterExceptionHandler? previousFlutterHandler;
  late bool Function(Object, StackTrace)? previousAsyncHandler;

  setUp(() {
    previousFlutterHandler = FlutterError.onError;
    previousAsyncHandler = PlatformDispatcher.instance.onError;
  });

  tearDown(() {
    FlutterError.onError = previousFlutterHandler;
    PlatformDispatcher.instance.onError = previousAsyncHandler;
  });

  test('captures framework failures and invokes the existing handler', () {
    final store = LogStore();
    var existingHandlerCalled = false;
    FlutterError.onError = (details) {
      existingHandlerCalled = details.exception is StateError;
    };
    final collector = DebugErrorCollector(store.addEntry)..install();
    final stack = StackTrace.current;

    FlutterError.onError!(FlutterErrorDetails(
      exception: StateError('framework crash'),
      stack: stack,
    ));

    collector.dispose();
    expect(existingHandlerCalled, isTrue);
    final entry = store.getStructuredLogs().single;
    expect(entry['source'], 'FlutterError');
    expect(entry['severity'], 'error');
    expect(entry['message'], contains('framework crash'));
    expect(entry['error'], contains('framework crash'));
    expect(entry['stack'], contains('debug_error_collector_test.dart'));
  });

  test('captures root async failures and preserves handled result', () {
    final store = LogStore();
    var existingHandlerCalled = false;
    PlatformDispatcher.instance.onError = (error, stack) {
      existingHandlerCalled = error is StateError;
      return true;
    };
    final collector = DebugErrorCollector(store.addEntry)..install();
    final stack = StackTrace.current;

    final handled = PlatformDispatcher.instance.onError!(
      StateError('async crash'),
      stack,
    );

    collector.dispose();
    expect(handled, isTrue);
    expect(existingHandlerCalled, isTrue);
    final entry = store.getStructuredLogs().single;
    expect(entry['source'], 'PlatformDispatcher');
    expect(entry['severity'], 'error');
    expect(entry['error'], contains('async crash'));
    expect(entry['stack'], contains('debug_error_collector_test.dart'));
  });

  test('crash and disconnect evidence remains queryable as a log delta', () {
    final store = LogStore();
    store.addEntry(LogEntry(
      timestamp: DateTime.utc(2026, 7, 29, 12),
      severity: LogSeverity.error,
      source: 'FlutterError',
      message: 'app crash',
      error: StateError('app crash'),
      stack: StackTrace.current,
    ));
    store.addEntry(LogEntry(
      timestamp: DateTime.utc(2026, 7, 29, 12, 1),
      severity: LogSeverity.error,
      source: 'PlatformDispatcher',
      message: 'root async failure before disconnect',
      error: StateError('async failure'),
      stack: StackTrace.current,
    ));

    final delta = store.getLogSnapshot(afterSequence: 1);
    expect(delta['cursor'], 2);
    expect(delta['count'], 1);
    expect(
        (delta['entries'] as List).single['error'], contains('async failure'));
  });
}
