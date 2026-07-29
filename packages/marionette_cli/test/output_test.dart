import 'dart:convert';

import 'package:marionette_cli/src/cli/output.dart';
import 'package:marionette_mcp/src/contracts.dart';
import 'package:test/test.dart';

void main() {
  test('typed CLI documents encode stable JSON', () {
    final document = CliCaptureResult(
      outputDir: 'capture',
      elementsFile: 'capture/elements.json',
      logsFile: 'capture/logs.json',
      screenshots: const ['capture/screenshots/screenshot.png'],
      logCursor: 4,
      logCount: 1,
      afterSequence: 3,
    );

    final json = jsonDecode(const JsonEncoder.withIndent('  ').convert(
      document,
    ));

    expect(json, {
      'schemaVersion': 1,
      'protocolVersion': 1,
      'outputDir': 'capture',
      'elementsFile': 'capture/elements.json',
      'logsFile': 'capture/logs.json',
      'screenshots': ['capture/screenshots/screenshot.png'],
      'logCursor': 4,
      'logCount': 1,
      'afterSequence': 3,
    });
  });

  test('typed CLI operation nests typed connection contracts', () {
    final document = CliDoctorResult(
      instances: [
        ConnectionInfo.connected(
          uri: 'ws://127.0.0.1:8181/ws',
          connectedAt: DateTime.utc(2026, 1, 1),
        ),
      ],
      healthy: true,
    );

    final json = jsonDecode(jsonEncode(document)) as Map<String, dynamic>;

    expect(json['healthy'], isTrue);
    expect((json['instances'] as List).single['connected'], isTrue);
    expect((json['instances'] as List).single['uri'], 'ws://127.0.0.1:8181/ws');
  });
}
