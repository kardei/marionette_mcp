import 'package:logging/logging.dart' as logging;
import 'package:marionette_mcp/src/contracts.dart';
import 'package:mcp_dart/mcp_dart.dart';

/// Runs a gesture and preserves the legacy text response alongside a
/// diagnostic machine-readable outcome.
Future<CallToolResult> runDiagnosticGesture(
  logging.Logger logger,
  String gesture,
  Future<Map<String, dynamic>> Function() action,
) async {
  try {
    final response = await action();
    final outcome = DiagnosticGestureOutcome.fromResponse(gesture, response);
    return CallToolResult(
      content: [TextContent(text: outcome.message ?? 'Successfully $gesture')],
      structuredContent: outcome.toJson(),
    );
  } catch (error, stack) {
    logger.warning('Failed to $gesture', error, stack);
    final outcome = DiagnosticGestureOutcome.failure(gesture, error, stack);
    return CallToolResult(
      isError: true,
      content: [TextContent(text: error.toString())],
      structuredContent: outcome.toJson(),
    );
  }
}
// @marionette-codec-boundary: explicit JSON/VM/MCP codec boundary
