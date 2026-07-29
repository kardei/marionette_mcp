import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:marionette_cli/src/cli/output.dart';
import 'package:marionette_cli/src/instance_registry.dart';
import 'package:marionette_mcp/src/contracts.dart';
import 'package:marionette_mcp/src/vm_service/vm_service_connector.dart';

class DoctorCommand extends Command<int> {
  DoctorCommand(this._registry);

  final InstanceRegistry _registry;

  @override
  String get name => 'doctor';

  @override
  String get description =>
      'Check connectivity of all registered Flutter app instances.';

  @override
  Future<int> run() async {
    final instances = _registry.listAll();

    final jsonOutput =
        outputFormatFrom(globalResults?['format']) == OutputFormat.json;

    if (instances.isEmpty) {
      if (jsonOutput) {
        writeJson(const CliDoctorResult(instances: [], healthy: true));
      } else {
        stdout.writeln('No instances registered.');
      }
      return 0;
    }

    final rawTimeout = globalResults?['timeout'] as String? ?? '5';
    final timeoutSeconds = int.tryParse(rawTimeout);
    if (timeoutSeconds == null) {
      stderr.writeln('Invalid timeout value: "$rawTimeout"');
      return 64;
    }
    var allHealthy = true;
    final results = <ConnectionInfo>[];

    if (!jsonOutput) {
      stdout.writeln('Checking ${instances.length} instance(s)...\n');
    }

    for (final info in instances) {
      if (!jsonOutput) {
        stdout.write('  ${info.name} (${info.uri}) ... ');
      }
      final connector = VmServiceConnector();

      try {
        await connector
            .connect(info.uri)
            .timeout(Duration(seconds: timeoutSeconds));
        results.add(ConnectionInfo.connected(
          uri: info.uri,
          connectedAt: DateTime.now().toUtc(),
        ));
        if (!jsonOutput) stdout.writeln('OK');
      } catch (e) {
        results.add(ConnectionInfo(
          connected: false,
          uri: info.uri,
          error: e.toString(),
        ));
        if (!jsonOutput) stdout.writeln('FAILED');
        if (!jsonOutput) stderr.writeln('    $e');
        allHealthy = false;
      } finally {
        try {
          await connector.disconnect();
        } catch (_) {}
      }
    }

    if (jsonOutput) {
      writeJson(CliDoctorResult(instances: results, healthy: allHealthy));
      return allHealthy ? 0 : 1;
    }

    stdout.writeln();
    if (allHealthy) {
      stdout.writeln('All instances are reachable.');
    } else {
      stdout.writeln(
        'Some instances are unreachable. '
        'Use "marionette unregister --stale" to remove them.',
      );
    }

    return allHealthy ? 0 : 1;
  }
}
