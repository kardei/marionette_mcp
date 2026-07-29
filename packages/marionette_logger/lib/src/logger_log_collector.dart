import 'package:logger/logger.dart';
import 'package:marionette_flutter/src/services/log_collector.dart';
import 'package:marionette_flutter/src/services/log_entry.dart';

/// A [LogCollector] that also serves as a [LogOutput] for the logger package.
///
/// This class implements both interfaces, allowing you to pass the same object
/// to both [MarionetteConfiguration] and [Logger].
///
/// ## Example
///
/// ```dart
/// import 'package:logger/logger.dart';
/// import 'package:marionette_flutter/marionette_flutter.dart';
/// import 'package:marionette_logger/marionette_logger.dart';
///
/// void main() {
///   final logCollector = LoggerLogCollector();
///
///   MarionetteBinding.ensureInitialized(
///     MarionetteConfiguration(logCollector: logCollector),
///   );
///
///   // Pass the same object as LogOutput to Logger
///   final logger = Logger(
///     output: MultiOutput([
///       ConsoleOutput(),
///       logCollector, // Same object, used as LogOutput
///     ]),
///   );
///
///   logger.d('Debug message');
///   runApp(MyApp());
/// }
/// ```
class LoggerLogCollector extends LogOutput implements LogCollector {
  void Function(String)? _onLog;

  // LogCollector implementation

  @override
  void start(void Function(String log) onLog) {
    _onLog = onLog;
  }

  @override
  void startStructured(void Function(LogEntry entry) onLog) {
    _onLog = (message) => onLog(LogEntry.fromLegacy(
          message: message,
          timestamp: DateTime.now(),
          severity: 'info',
          source: 'legacy',
        ));
  }

  @override
  void dispose() {
    _onLog = null;
  }

  // LogOutput implementation

  @override
  void output(OutputEvent event) {
    for (final line in event.lines) {
      _onLog?.call(line);
    }
  }
}
