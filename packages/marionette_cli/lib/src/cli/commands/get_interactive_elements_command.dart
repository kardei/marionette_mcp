import 'dart:io';

import 'package:marionette_cli/src/cli/instance_command.dart';
import 'package:marionette_cli/src/cli/output.dart';
import 'package:marionette_cli/src/instance_registry.dart';
import 'package:marionette_mcp/src/formatting.dart';
import 'package:marionette_mcp/src/vm_service/vm_service_connector.dart';
import 'package:marionette_mcp/src/vm_service/vm_service_connector_contracts.dart';

class ElementsCommand extends InstanceCommand {
  ElementsCommand(this._registry);

  final InstanceRegistry _registry;

  @override
  InstanceRegistry get registry => _registry;

  @override
  String get name => 'get-interactive-elements';

  @override
  String get description =>
      'List interactive elements in the Flutter app UI tree.';

  @override
  Future<int> execute(VmServiceConnector connector) async {
    final snapshot = await connector.getInteractiveElementSnapshot();

    if (outputFormat == OutputFormat.json) {
      writeJson(snapshot);
      return 0;
    }

    stdout.writeln('Found ${snapshot.count} interactive element(s):\n');

    for (final element in snapshot.elements) {
      stdout.writeln(formatElement(element.toJson()));
    }

    return 0;
  }
}
