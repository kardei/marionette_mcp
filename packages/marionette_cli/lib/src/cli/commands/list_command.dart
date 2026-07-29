import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:marionette_cli/src/cli/output.dart';
import 'package:marionette_cli/src/instance_registry.dart';

class ListCommand extends Command<int> {
  ListCommand(this._registry);

  final InstanceRegistry _registry;

  @override
  String get name => 'list';

  @override
  String get description => 'List all registered Flutter app instances.';

  @override
  int run() {
    final instances = _registry.listAll();

    if (outputFormatFrom(globalResults?['format']) == OutputFormat.json) {
      writeJson(CliInstanceListResult(instances));
      return 0;
    }

    if (instances.isEmpty) {
      stdout.writeln('No instances registered.');
      return 0;
    }

    stdout.writeln('Registered instances:\n');
    for (final info in instances) {
      stdout.writeln('  ${info.name}');
      stdout.writeln('    URI: ${info.uri}');
      stdout.writeln('    Registered: ${info.registeredAt.toLocal()}');
      stdout.writeln();
    }

    return 0;
  }
}
