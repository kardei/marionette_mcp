import 'dart:io';

import 'package:marionette_cli/src/cli/instance_command.dart';
import 'package:marionette_cli/src/cli/output.dart';
import 'package:marionette_cli/src/instance_registry.dart';
import 'package:marionette_mcp/src/vm_service/vm_service_connector.dart';

class HotReloadCommand extends InstanceCommand {
  HotReloadCommand(this._registry);

  final InstanceRegistry _registry;

  @override
  InstanceRegistry get registry => _registry;

  @override
  String get name => 'hot-reload';

  @override
  String get description => 'Perform a hot reload of the Flutter app.';

  @override
  Future<int> execute(VmServiceConnector connector) async {
    final reloaded = await connector.hotReload();

    if (reloaded) {
      if (outputFormat == OutputFormat.json) {
        writeJson(
          const CliOperationResult(operation: 'hot_reload', success: true),
        );
      } else {
        stdout.writeln('Hot reload completed successfully.');
      }
      return 0;
    } else {
      if (outputFormat == OutputFormat.json) {
        writeJson(
          const CliOperationResult(operation: 'hot_reload', success: false),
        );
      } else {
        stderr.writeln('Hot reload failed. The app may need a full restart.');
      }
      return 1;
    }
  }
}
