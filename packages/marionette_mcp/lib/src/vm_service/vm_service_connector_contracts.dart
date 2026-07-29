import 'package:marionette_mcp/src/contracts.dart';
import 'package:marionette_mcp/src/vm_service/vm_service_connector.dart';

/// Typed views over the existing VM/MCP JSON boundary.
extension VmServiceConnectorContracts on VmServiceConnector {
  Future<InteractiveElementSnapshot> getInteractiveElementSnapshot() async {
    final response = await getInteractiveElements();
    return InteractiveElementSnapshot.fromJson(response);
  }

  Future<LogSnapshot> getLogSnapshot({int? afterSequence}) async {
    final response = await callCustomExtension(
      'marionette.getLogs',
      {
        if (afterSequence != null) 'afterSequence': afterSequence.toString(),
      },
    );
    return LogSnapshot.fromJson(response);
  }
}
// @marionette-codec-boundary: explicit JSON/VM/MCP codec boundary
