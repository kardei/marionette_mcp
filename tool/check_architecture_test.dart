import 'dart:io';

import 'package:test/test.dart';

import 'check_architecture.dart';

void main() {
  late Directory workspace;

  setUp(() {
    workspace = Directory.systemTemp.createTempSync('marionette_arch_');
  });

  tearDown(() {
    if (workspace.existsSync()) workspace.deleteSync(recursive: true);
  });

  void write(String path, String contents) {
    final file = File.fromUri(workspace.uri.resolve(path));
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(contents);
  }

  test('production detection handles relative and Windows/POSIX paths', () {
    expect(isProductionSource(File('packages/foo/lib/src/file.dart')), isTrue);
    expect(
      isProductionSource(File(r'D:\workspace\packages\foo\lib\file.dart')),
      isTrue,
    );
    expect(
      isProductionSource(File('/workspace/packages/foo/lib/file.dart')),
      isTrue,
    );
    expect(
      isProductionSource(File('packages/foo/example/lib/file.dart')),
      isFalse,
    );
  });

  test('negative fixture detects a handwritten file over 500 lines', () {
    write(
      'packages/foo/lib/too_long.dart',
      List<String>.filled(501, '// production line').join('\n'),
    );

    final report = scanArchitecture(workspace);

    expect(
      report.violations,
      contains(matches(RegExp(r'^501\t.*too_long\.dart$'))),
    );
  });

  test('negative fixture detects raw JSON without a codec boundary', () {
    write(
      'packages/foo/lib/raw.dart',
      'class Raw { Map<String, dynamic> value = <String, dynamic>{}; }',
    );

    final report = scanArchitecture(workspace);

    expect(
      report.violations,
      contains(matches(RegExp(r'^raw JSON map without codec boundary marker'))),
    );
  });

  test('marked codec boundary is allowed while an import cycle is rejected',
      () {
    write(
      'packages/foo/lib/codec.dart',
      '// @marionette-codec-boundary: test codec\n'
          'class Codec { Map<String, dynamic> value = <String, dynamic>{}; }',
    );
    write('packages/foo/lib/a.dart', "import 'b.dart';\nclass A {}\n");
    write('packages/foo/lib/b.dart', "import 'a.dart';\nclass B {}\n");

    final report = scanArchitecture(workspace);

    expect(
      report.violations,
      isNot(contains(matches(RegExp(r'raw JSON map without codec boundary')))),
    );
    expect(
      report.violations,
      contains(matches(RegExp(r'^dependency cycle\t'))),
    );
  });
}
