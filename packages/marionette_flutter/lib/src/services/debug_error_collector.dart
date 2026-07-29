import 'package:flutter/foundation.dart';
import 'package:marionette_flutter/src/services/log_entry.dart';

/// Installs chained debug error handlers that write framework and root async
/// failures to the structured Marionette log stream.
class DebugErrorCollector {
  DebugErrorCollector(this._sink);

  final void Function(LogEntry entry) _sink;
  FlutterExceptionHandler? _previousFlutterErrorHandler;
  bool Function(Object error, StackTrace stack)? _previousAsyncErrorHandler;
  late final FlutterExceptionHandler _flutterErrorHandler = _handleFlutterError;
  late final bool Function(Object error, StackTrace stack) _asyncErrorHandler =
      _handleAsyncError;
  bool _installed = false;

  /// Installs the handlers once and remembers the handlers already installed
  /// by the app or another package.
  void install() {
    if (_installed) return;
    _previousFlutterErrorHandler = FlutterError.onError;
    _previousAsyncErrorHandler = PlatformDispatcher.instance.onError;
    FlutterError.onError = _flutterErrorHandler;
    PlatformDispatcher.instance.onError = _asyncErrorHandler;
    _installed = true;
  }

  /// Restores handlers only when they still point to this collector. This
  /// avoids overwriting a handler installed later by the host application.
  void dispose() {
    if (!_installed) return;
    if (identical(FlutterError.onError, _flutterErrorHandler)) {
      FlutterError.onError = _previousFlutterErrorHandler;
    }
    if (identical(PlatformDispatcher.instance.onError, _asyncErrorHandler)) {
      PlatformDispatcher.instance.onError = _previousAsyncErrorHandler;
    }
    _installed = false;
  }

  void _handleFlutterError(FlutterErrorDetails details) {
    _record(
      LogEntry(
        timestamp: DateTime.now(),
        severity: LogSeverity.error,
        source: 'FlutterError',
        message: details.exceptionAsString(),
        error: details.exception,
        stack: details.stack,
      ),
    );

    final previous = _previousFlutterErrorHandler;
    if (previous != null) {
      previous(details);
    } else {
      FlutterError.presentError(details);
    }
  }

  bool _handleAsyncError(Object error, StackTrace stack) {
    _record(
      LogEntry(
        timestamp: DateTime.now(),
        severity: LogSeverity.error,
        source: 'PlatformDispatcher',
        message: error.toString(),
        error: error,
        stack: stack,
      ),
    );
    return _previousAsyncErrorHandler?.call(error, stack) ?? false;
  }

  void _record(LogEntry entry) {
    // Diagnostics must never change whether Flutter reports or propagates an
    // error if a user-provided sink is unavailable or misbehaves.
    try {
      _sink(entry);
    } catch (_) {
      // Deliberately ignored: the original framework/root handler still runs.
    }
  }
}
