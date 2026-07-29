import 'package:marionette_flutter/src/services/log_entry.dart';

/// Abstract interface for collecting application logs.
///
/// Implementations of this interface are responsible for capturing logs from
/// various sources (e.g., the `logging` package, `logger` package, or custom
/// logging solutions) and forwarding them to the Marionette system.
///
/// See also:
/// - [PrintLogCollector] - A generic implementation that can be used with any
///   logging solution by calling [PrintLogCollector.addLog].
/// - `LoggingLogCollector` from `marionette_logging` - For the `logging` package.
/// - `LoggerLogCollector` from `marionette_logger` - For the `logger` package.
abstract class LogCollector {
  /// Starts collecting logs.
  ///
  /// This method is called once during initialization. The [onLog] callback
  /// should be invoked whenever a new log entry is captured.
  ///
  /// The log message passed to [onLog] should be pre-formatted as a string.
  void start(void Function(String log) onLog);

  /// Starts structured collection in addition to the legacy string API.
  ///
  /// Existing collectors only need to implement [start]. The default adapter
  /// keeps them source-compatible while identifying the event as legacy.
  void startStructured(void Function(LogEntry entry) onLog) {
    start((log) => onLog(LogEntry.fromLegacy(
          message: log,
          timestamp: DateTime.now(),
          severity: 'info',
          source: 'legacy',
        )));
  }

  /// Stops collecting logs and releases any resources.
  ///
  /// After calling this method, no more logs should be forwarded to the
  /// callback provided in [start].
  void dispose();
}
