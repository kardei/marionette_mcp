import 'dart:io';

import 'package:marionette_cli/src/cli/instance_command.dart';
import 'package:marionette_cli/src/instance_registry.dart';
import 'package:marionette_cli/src/cli/output.dart';
import 'package:marionette_mcp/src/vm_service/vm_service_connector.dart';
import 'package:marionette_mcp/src/vm_service/vm_service_connector_contracts.dart';

class LogsCommand extends InstanceCommand {
  LogsCommand(this._registry) {
    argParser.addOption(
      'after-sequence',
      help: 'Only show logs with a sequence greater than this cursor.',
    );
  }

  final InstanceRegistry _registry;

  @override
  InstanceRegistry get registry => _registry;

  @override
  String get name => 'get-logs';

  @override
  String get description => 'Retrieve application logs from the Flutter app.';

  @override
  Future<int> execute(VmServiceConnector connector) async {
    final rawAfter = argResults?['after-sequence'] as String?;
    final afterSequence = rawAfter == null ? null : int.tryParse(rawAfter);
    if (rawAfter != null && afterSequence == null) {
      usageException('--after-sequence must be an integer.');
    }
    final snapshot = await connector.getLogSnapshot(
      afterSequence: afterSequence,
    );

    if (outputFormat == OutputFormat.json) {
      writeJson(snapshot);
      return 0;
    }

    final logs = snapshot.legacyLogs;
    final count = snapshot.count;

    if (count == 0) {
      stdout.writeln('No logs collected.');
      return 0;
    }

    stdout.writeln('Collected $count log entr${count == 1 ? 'y' : 'ies'}:\n');
    for (final log in logs) {
      stdout.writeln(log);
    }

    return 0;
  }
}
