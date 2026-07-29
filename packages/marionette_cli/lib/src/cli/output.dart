import 'dart:convert';
import 'dart:io';

import 'package:marionette_mcp/src/contracts.dart';

enum OutputFormat { text, json }

/// Typed CLI documents keep command output stable while their [toJson]
/// methods remain the single JSON codec boundary.
class CliOperationResult {
  const CliOperationResult({required this.operation, required this.success});

  final String operation;
  final bool success;

  Map<String, Object?> toJson() => {
        'schemaVersion': contractSchemaVersion,
        'protocolVersion': contractProtocolVersion,
        'operation': operation,
        'success': success,
      };
}

class CliCaptureResult {
  const CliCaptureResult({
    required this.outputDir,
    required this.elementsFile,
    required this.logsFile,
    required this.screenshots,
    required this.logCursor,
    required this.logCount,
    this.afterSequence,
  });

  final String outputDir;
  final String elementsFile;
  final String logsFile;
  final List<String> screenshots;
  final int logCursor;
  final int logCount;
  final int? afterSequence;

  Map<String, Object?> toJson() => {
        'schemaVersion': contractSchemaVersion,
        'protocolVersion': contractProtocolVersion,
        'outputDir': outputDir,
        'elementsFile': elementsFile,
        'logsFile': logsFile,
        'screenshots': screenshots,
        'logCursor': logCursor,
        'logCount': logCount,
        if (afterSequence != null) 'afterSequence': afterSequence,
      };
}

class CliScreenshotResult {
  const CliScreenshotResult(this.screenshots);

  final List<String> screenshots;

  Map<String, Object?> toJson() => {
        'schemaVersion': contractSchemaVersion,
        'protocolVersion': contractProtocolVersion,
        'screenshots': screenshots,
      };
}

class CliInstanceListResult {
  const CliInstanceListResult(this.instances);

  final List<Object> instances;

  Map<String, Object?> toJson() => {
        'schemaVersion': contractSchemaVersion,
        'protocolVersion': contractProtocolVersion,
        'instances': instances,
      };
}

class CliDoctorResult {
  const CliDoctorResult({required this.instances, required this.healthy});

  final List<ConnectionInfo> instances;
  final bool healthy;

  Map<String, Object?> toJson() => {
        'schemaVersion': contractSchemaVersion,
        'protocolVersion': contractProtocolVersion,
        'instances': instances,
        'healthy': healthy,
      };
}

OutputFormat outputFormatFrom(Object? value) {
  return value == 'json' ? OutputFormat.json : OutputFormat.text;
}

void writeJson(Object value) {
  stdout.writeln(const JsonEncoder.withIndent('  ').convert(value));
}

void writeGestureOutput({
  required OutputFormat format,
  required String gesture,
  required Map<String, dynamic> response,
  required String fallbackMessage,
}) {
  final outcome = DiagnosticGestureOutcome.fromResponse(gesture, response);
  if (format == OutputFormat.json) {
    writeJson(outcome);
  } else {
    stdout.writeln(outcome.message ?? fallbackMessage);
  }
}
// @marionette-codec-boundary: explicit JSON/VM/MCP codec boundary
