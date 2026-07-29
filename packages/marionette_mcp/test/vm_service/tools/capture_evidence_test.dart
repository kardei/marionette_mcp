import 'dart:convert';
import 'dart:io';

import 'package:marionette_mcp/src/contracts.dart';
import 'package:marionette_mcp/src/vm_service/tools/capture_evidence.dart';
import 'package:test/test.dart';

const _onePixelPng =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=';

LogSnapshot _logs() => LogSnapshot(
      entries: [
        StructuredLogEntry(
          sequence: 2,
          timestamp: DateTime.utc(2026, 7, 29, 12),
          severity: LogSeverity.error,
          source: 'test',
          message: 'failure',
          error: 'StateError',
          stack: 'stack',
        ),
      ],
      cursor: 2,
      afterSequence: 1,
    );

void main() {
  late Directory parent;

  setUp(() {
    parent = Directory.systemTemp.createTempSync('marionette_capture_');
  });

  tearDown(() {
    if (parent.existsSync()) parent.deleteSync(recursive: true);
  });

  test('publishes complete evidence atomically with typed paths and cursor',
      () async {
    final target = '${parent.path}${Platform.pathSeparator}checkpoint';
    final evidence = await publishCaptureEvidence(
      outputDirectory: target,
      elements: InteractiveElementSnapshot(elements: const []),
      logs: _logs(),
      screenshots: const [_onePixelPng],
    );

    expect(evidence.toJson()['schemaVersion'], contractSchemaVersion);
    expect(evidence.logCursor, 2);
    expect(File(evidence.elementsPath).existsSync(), isTrue);
    expect(File(evidence.logsPath).existsSync(), isTrue);
    expect(evidence.screenshotPaths, hasLength(1));
    expect(
      File(evidence.screenshotPaths.single).readAsBytesSync().sublist(0, 4),
      [137, 80, 78, 71],
    );
    final logs = jsonDecode(File(evidence.logsPath).readAsStringSync());
    expect(logs['cursor'], 2);
    expect(logs['afterSequence'], 1);
  });

  test('rejects overwrite and corrupt screenshot evidence', () async {
    final target = Directory(
      '${parent.path}${Platform.pathSeparator}existing',
    )..createSync();
    final sentinel = File(
      '${target.path}${Platform.pathSeparator}sentinel.txt',
    )..writeAsStringSync('keep');

    await expectLater(
      publishCaptureEvidence(
        outputDirectory: target.path,
        elements: InteractiveElementSnapshot(elements: const []),
        logs: _logs(),
        screenshots: const [_onePixelPng],
      ),
      throwsA(isA<ContractFormatException>()),
    );
    expect(sentinel.readAsStringSync(), 'keep');

    final corruptTarget = '${parent.path}${Platform.pathSeparator}corrupt';
    await expectLater(
      publishCaptureEvidence(
        outputDirectory: corruptTarget,
        elements: InteractiveElementSnapshot(elements: const []),
        logs: _logs(),
        screenshots: const ['not-png'],
      ),
      throwsA(isA<ContractFormatException>()),
    );
    expect(Directory(corruptTarget).existsSync(), isFalse);
  });
}
