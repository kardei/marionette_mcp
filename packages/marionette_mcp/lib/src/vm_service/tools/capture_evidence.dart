// @marionette-codec-boundary: capture evidence JSON/filesystem codec

import 'dart:convert';
import 'dart:io';

import 'package:marionette_mcp/src/contracts.dart';

const _pngSignature = <int>[137, 80, 78, 71, 13, 10, 26, 10];

/// Publishes a complete capture by renaming a fully written staging directory.
/// The target directory must not exist; this prevents overwriting evidence.
Future<CaptureEvidence> publishCaptureEvidence({
  required String outputDirectory,
  required InteractiveElementSnapshot elements,
  required LogSnapshot logs,
  required List<String> screenshots,
}) async {
  final target = _captureTarget(outputDirectory);
  final parent = target.parent;
  if (FileSystemEntity.typeSync(parent.path, followLinks: false) ==
      FileSystemEntityType.file) {
    throw ContractFormatException(
      'output directory parent is a file',
      path: outputDirectory,
    );
  }

  try {
    parent.createSync(recursive: true);
  } on FileSystemException catch (error) {
    throw ContractFormatException(
      'cannot create output directory parent: $error',
      path: outputDirectory,
    );
  }

  final staging = Directory(
    '${parent.path}${Platform.pathSeparator}.marionette-capture-${pid}-${DateTime.now().microsecondsSinceEpoch}',
  );
  if (staging.existsSync()) {
    throw ContractFormatException(
      'staging directory already exists',
      path: outputDirectory,
    );
  }

  final screenshotPaths = <String>[];
  try {
    staging.createSync();
    _writeJson(
      File('${staging.path}${Platform.pathSeparator}elements.json'),
      elements.toJson(),
    );
    _writeJson(
      File('${staging.path}${Platform.pathSeparator}logs.json'),
      logs.toJson(),
    );

    final screenshotDirectory = Directory(
      '${staging.path}${Platform.pathSeparator}screenshots',
    )..createSync();
    for (var i = 0; i < screenshots.length; i++) {
      final bytes = _decodePng(screenshots[i], i);
      final name = 'screenshot${i == 0 ? '' : '_$i'}.png';
      final file = File(
        '${screenshotDirectory.path}${Platform.pathSeparator}$name',
      );
      file.writeAsBytesSync(bytes, flush: true);
      screenshotPaths.add(file.path);
    }

    final published = staging.renameSync(target.path);
    return CaptureEvidence(
      outputDirectory: published.path,
      elementsPath: File(
        '${published.path}${Platform.pathSeparator}elements.json',
      ).path,
      logsPath: File(
        '${published.path}${Platform.pathSeparator}logs.json',
      ).path,
      screenshotPaths: [
        for (final path in screenshotPaths)
          path.replaceFirst(staging.path, published.path),
      ],
      logCursor: logs.cursor,
      logCount: logs.count,
      afterSequence: logs.afterSequence,
    );
  } on ContractFormatException {
    _deleteStaging(staging);
    rethrow;
  } on Object catch (error) {
    _deleteStaging(staging);
    throw ContractFormatException(
      'capture could not be published atomically: $error',
      path: outputDirectory,
    );
  }
}

Directory _captureTarget(String outputDirectory) {
  if (outputDirectory.trim().isEmpty || outputDirectory.contains('\u0000')) {
    throw const ContractFormatException(
      'output directory must be a non-empty valid path',
      path: 'output_dir',
    );
  }
  final target = Directory(outputDirectory).absolute;
  if (target.path == target.parent.path) {
    throw const ContractFormatException(
      'output directory must not be a filesystem root',
      path: 'output_dir',
    );
  }
  if (target.existsSync() ||
      FileSystemEntity.typeSync(target.path, followLinks: false) !=
          FileSystemEntityType.notFound) {
    throw const ContractFormatException(
      'output directory already exists; refusing to overwrite evidence',
      path: 'output_dir',
    );
  }
  return target;
}

void _writeJson(File file, Map<String, dynamic> value) {
  file.writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert(value),
    flush: true,
  );
}

List<int> _decodePng(String value, int index) {
  late final List<int> bytes;
  try {
    bytes = base64Decode(value);
  } on FormatException {
    throw ContractFormatException(
      'screenshot must be valid base64 PNG data',
      path: 'screenshots[$index]',
    );
  }
  if (bytes.length < _pngSignature.length ||
      !_pngSignature
          .asMap()
          .entries
          .every((entry) => bytes[entry.key] == entry.value)) {
    throw ContractFormatException(
      'screenshot must contain a PNG signature',
      path: 'screenshots[$index]',
    );
  }
  return bytes;
}

void _deleteStaging(Directory staging) {
  try {
    if (staging.existsSync()) staging.deleteSync(recursive: true);
  } on Object {
    // Cleanup is best effort and must not mask the typed publication failure.
  }
}
