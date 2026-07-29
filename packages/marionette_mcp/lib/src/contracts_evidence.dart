// @marionette-codec-boundary: explicit JSON/VM/MCP codec boundary
part of marionette_contracts;

/// Published files from a read-only MCP capture checkpoint.
class CaptureEvidence {
  const CaptureEvidence({
    required this.outputDirectory,
    required this.elementsPath,
    required this.logsPath,
    required this.screenshotPaths,
    required this.logCursor,
    required this.logCount,
    this.afterSequence,
  });

  final String outputDirectory;
  final String elementsPath;
  final String logsPath;
  final List<String> screenshotPaths;
  final int logCursor;
  final int logCount;
  final int? afterSequence;

  Map<String, dynamic> toJson() => {
        'schemaVersion': contractSchemaVersion,
        'protocolVersion': contractProtocolVersion,
        'outputDirectory': outputDirectory,
        'elementsPath': elementsPath,
        'logsPath': logsPath,
        'screenshotPaths': screenshotPaths,
        'logCursor': logCursor,
        'logCount': logCount,
        if (afterSequence != null) 'afterSequence': afterSequence,
      };
}

/// Machine-readable result for a gesture diagnostic call.
class DiagnosticGestureOutcome {
  DiagnosticGestureOutcome({
    required this.gesture,
    required this.success,
    required this.status,
    required this.timestamp,
    this.message,
    this.error,
    this.stack,
  });

  factory DiagnosticGestureOutcome.fromResponse(
    String gesture,
    Map<String, dynamic> response,
  ) {
    return DiagnosticGestureOutcome(
      gesture: gesture,
      success: true,
      status: 'success',
      timestamp: DateTime.now().toUtc(),
      message: _optionalString(response, 'message'),
    );
  }

  factory DiagnosticGestureOutcome.failure(
    String gesture,
    Object error,
    StackTrace stack,
  ) {
    return DiagnosticGestureOutcome(
      gesture: gesture,
      success: false,
      status: 'error',
      timestamp: DateTime.now().toUtc(),
      error: error.toString(),
      stack: stack.toString(),
    );
  }

  final String gesture;
  final bool success;
  final String status;
  final DateTime timestamp;
  final String? message;
  final String? error;
  final String? stack;

  Map<String, dynamic> toJson() => {
        'schemaVersion': contractSchemaVersion,
        'protocolVersion': contractProtocolVersion,
        'gesture': gesture,
        'success': success,
        'status': status,
        'timestamp': timestamp.toUtc().toIso8601String(),
        'message': message,
        'error': error,
        'stack': stack,
      };
}
