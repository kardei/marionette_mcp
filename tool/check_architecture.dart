import 'dart:io';

const maxProductionLines = 500;
const codecBoundaryMarker = '@marionette-codec-boundary:';

final rawMapPattern = RegExp(r'Map<String,\s*(?:dynamic|Object\?>)');
final rawJsonPattern = RegExp(
  r'(?:jsonEncode|jsonDecode|JsonEncoder|JsonDecoder|structuredContent\s*:|'
  r'callCustomExtension\s*\()',
);

/// The result of scanning one workspace for production architecture rules.
class ArchitectureReport {
  const ArchitectureReport(this.violations);

  final List<String> violations;

  bool get passed => violations.isEmpty;
}

/// Returns true for handwritten package `lib`/`bin` production sources.
///
/// The check is segment-based rather than substring-based, so it works for
/// relative paths (`packages/foo/lib/a.dart`), absolute Windows paths, and
/// absolute POSIX paths alike. Package examples are deliberately excluded.
bool isProductionSource(File file) {
  final segments = _pathSegments(file.path);
  final packagesIndex = segments.lastIndexOf('packages');
  if (packagesIndex < 0 || packagesIndex + 2 >= segments.length) {
    return false;
  }
  return segments[packagesIndex + 2] == 'lib' ||
      segments[packagesIndex + 2] == 'bin';
}

bool isGenerated(File file) {
  final segments = _pathSegments(file.path);
  return file.path.replaceAll('\\', '/').toLowerCase().endsWith('.g.dart') ||
      segments.contains('generated') ||
      segments.contains('.dart_tool');
}

/// Scans [workspaceRoot] without changing files or relying on the cwd shape.
ArchitectureReport scanArchitecture(Directory workspaceRoot) {
  final root = Directory(workspaceRoot.absolute.path);
  final packages = Directory(_join(root.path, 'packages'));
  if (!packages.existsSync()) {
    return const ArchitectureReport(['packages/ directory not found']);
  }

  final productionFiles = [
    for (final entity in packages.listSync(recursive: true))
      if (entity is File && isProductionSource(entity) && !isGenerated(entity))
        entity,
  ];
  final violations = <String>[];
  for (final file in productionFiles) {
    final source = file.readAsStringSync();
    final lines = _lineCount(source);
    if (lines > maxProductionLines) {
      violations.add('$lines\t${file.path}');
    }
    if ((rawMapPattern.hasMatch(source) || rawJsonPattern.hasMatch(source)) &&
        !source.contains(codecBoundaryMarker)) {
      violations
          .add('raw JSON map without codec boundary marker\t${file.path}');
    }
  }

  for (final cycle in _findImportCycles(
    _localImportGraph(root, productionFiles),
  )) {
    violations.add('dependency cycle\t$cycle');
  }
  return ArchitectureReport(List.unmodifiable(violations..sort()));
}

Map<String, List<String>> _localImportGraph(
  Directory workspaceRoot,
  List<File> productionFiles,
) {
  final files = <String, File>{
    for (final file in productionFiles) _key(file): file,
  };
  final graph = <String, List<String>>{};
  final importPattern = RegExp(
    r'''^\s*(?:import|export)\s+['"]([^'"]+)['"]''',
    multiLine: true,
  );
  for (final entry in files.entries) {
    final imports = <String>[];
    final source = entry.value.readAsStringSync();
    for (final match in importPattern.allMatches(source)) {
      final uri = match.group(1)!;
      final target = _resolveImport(workspaceRoot, entry.value, uri);
      final targetKey = target == null ? null : _key(target);
      if (targetKey != null && files.containsKey(targetKey)) {
        imports.add(targetKey);
      }
    }
    graph[entry.key] = imports;
  }
  return graph;
}

File? _resolveImport(Directory workspaceRoot, File source, String uri) {
  if (uri.startsWith('package:')) {
    final packageParts = uri.substring('package:'.length).split('/');
    if (packageParts.length < 2) return null;
    final packagePath = _join(
      _join(_join(workspaceRoot.path, 'packages'), packageParts.first),
      'lib',
    );
    return File(_join(packagePath, packageParts.skip(1).join('/')));
  }
  if (uri.startsWith('.') || !uri.contains(':')) {
    return File.fromUri(source.parent.uri.resolve(uri));
  }
  return null;
}

int _lineCount(String source) {
  if (source.isEmpty) return 0;
  final count = source.split('\n').length;
  return source.endsWith('\n') ? count - 1 : count;
}

String _join(String base, String child) {
  return '$base${Platform.pathSeparator}${child.replaceAll('/', Platform.pathSeparator)}';
}

String _key(File file) {
  final normalized = file.absolute.path.replaceAll('\\', '/');
  return Platform.isWindows ? normalized.toLowerCase() : normalized;
}

List<String> _pathSegments(String path) {
  return path
      .replaceAll('\\', '/')
      .split('/')
      .where((segment) => segment.isNotEmpty)
      .map((segment) => segment.toLowerCase())
      .toList();
}

List<String> _findImportCycles(Map<String, List<String>> graph) {
  final visited = <String>{};
  final stack = <String>[];
  final cycles = <String>[];

  void visit(String node) {
    final cycleStart = stack.indexOf(node);
    if (cycleStart >= 0) {
      cycles.add([...stack.sublist(cycleStart), node].join(' -> '));
      return;
    }
    if (!visited.add(node)) return;
    stack.add(node);
    for (final next in graph[node] ?? const <String>[]) {
      visit(next);
    }
    stack.removeLast();
  }

  for (final node in graph.keys) {
    visit(node);
  }
  return cycles.toSet().toList()..sort();
}

void main([List<String> args = const []]) {
  final root = Directory(args.isEmpty ? Directory.current.path : args.first);
  final report = scanArchitecture(root);
  if (report.passed) {
    stdout.writeln(
      'Architecture check passed: <= 500 lines, marked JSON codec boundaries, and no local import cycles.',
    );
    return;
  }

  stderr.writeln('Architecture check failed:');
  for (final violation in report.violations) {
    stderr.writeln('  $violation');
  }
  exitCode = 1;
}
