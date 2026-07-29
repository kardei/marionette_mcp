import 'dart:convert';
import 'dart:io';

import 'package:marionette_cli/src/cli/instance_command.dart';
import 'package:marionette_cli/src/cli/output.dart';
import 'package:marionette_cli/src/instance_registry.dart';
import 'package:marionette_mcp/src/contracts.dart';
import 'package:marionette_mcp/src/vm_service/vm_service_connector.dart';
import 'package:marionette_mcp/src/vm_service/vm_service_connector_contracts.dart';
import 'package:path/path.dart' as p;

/// Captures read-only app state without exposing or invoking gesture APIs.
class CaptureCommand extends InstanceCommand {
  CaptureCommand(this._registry) {
    argParser
      ..addOption(
        'output-dir',
        help: 'Directory in which to save the capture.',
      )
      ..addOption(
        'output',
        help: 'Alias for --output-dir.',
      )
      ..addOption(
        'after-sequence',
        help: 'Only include logs with a sequence greater than this cursor.',
      );
  }

  final InstanceRegistry _registry;

  @override
  InstanceRegistry get registry => _registry;

  @override
  String get name => 'capture';

  @override
  String get description =>
      'Capture elements, screenshots, and a read-only log delta.';

  @override
  Future<int> execute(VmServiceConnector connector) async {
    final outputDir = _outputDirectory();
    final rawAfter = argResults?['after-sequence'] as String?;
    final afterSequence = rawAfter == null ? null : int.tryParse(rawAfter);
    if (rawAfter != null && afterSequence == null) {
      usageException('--after-sequence must be an integer.');
    }

    final directory = Directory(outputDir)..createSync(recursive: true);
    final snapshot = await connector.getInteractiveElementSnapshot();
    final logs = await connector.getLogSnapshot(afterSequence: afterSequence);
    final screenshotResponse = await connector.takeScreenshots();
    final rawScreenshots = screenshotResponse['screenshots'];
    if (rawScreenshots is! List) {
      throw const ContractFormatException(
        'screenshots must be a list',
        path: 'screenshots',
      );
    }
    final screenshots = <String>[];
    for (var i = 0; i < rawScreenshots.length; i++) {
      final screenshot = rawScreenshots[i];
      if (screenshot is! String) {
        throw ContractFormatException(
          'screenshot must be a base64 string',
          path: 'screenshots[$i]',
        );
      }
      screenshots.add(screenshot);
    }

    _writeJsonFile(p.join(directory.path, 'elements.json'), snapshot);
    _writeJsonFile(p.join(directory.path, 'logs.json'), logs);

    final screenshotPaths = <String>[];
    final screenshotDirectory = Directory(p.join(directory.path, 'screenshots'))
      ..createSync(recursive: true);
    for (var i = 0; i < screenshots.length; i++) {
      final file = File(
        p.join(
          screenshotDirectory.path,
          'screenshot${i == 0 ? '' : '_$i'}.png',
        ),
      );
      try {
        file.writeAsBytesSync(base64Decode(screenshots[i]));
      } on FormatException {
        throw ContractFormatException(
          'screenshot must contain valid base64 PNG data',
          path: 'screenshots[$i]',
        );
      }
      screenshotPaths.add(file.path);
    }

    final result = CliCaptureResult(
      outputDir: directory.path,
      elementsFile: p.join(directory.path, 'elements.json'),
      logsFile: p.join(directory.path, 'logs.json'),
      screenshots: screenshotPaths,
      logCursor: logs.cursor,
      logCount: logs.count,
      afterSequence: afterSequence,
    );

    if (outputFormat == OutputFormat.json) {
      writeJson(result);
    } else {
      stdout.writeln('Capture saved to ${directory.path}');
      stdout.writeln('  elements.json (${snapshot.count} elements)');
      stdout.writeln(
          '  logs.json (${logs.count} entries, cursor ${logs.cursor})');
      stdout.writeln('  screenshots/ (${screenshotPaths.length} image(s))');
    }
    return 0;
  }

  String _outputDirectory() {
    final outputDir = argResults?['output-dir'] as String?;
    final outputAlias = argResults?['output'] as String?;
    if (outputDir != null && outputAlias != null) {
      usageException('--output-dir and --output are mutually exclusive.');
    }
    final value = outputDir ?? outputAlias;
    if (value == null || value.isEmpty) {
      usageException('capture requires --output-dir <directory>.');
    }
    return value;
  }

  void _writeJsonFile(String path, Object value) {
    File(path)
      ..createSync(recursive: true)
      ..writeAsStringSync(const JsonEncoder.withIndent('  ').convert(value));
  }
}
// @marionette-codec-boundary: explicit JSON/VM/MCP codec boundary
