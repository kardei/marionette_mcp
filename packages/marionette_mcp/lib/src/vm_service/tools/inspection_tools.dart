import 'package:logging/logging.dart' as logging;
import 'package:marionette_mcp/src/contracts.dart';
import 'package:marionette_mcp/src/formatting.dart';
import 'package:marionette_mcp/src/vm_service/tools/capture_evidence.dart';
import 'package:marionette_mcp/src/vm_service/tools/tool_runner.dart';
import 'package:marionette_mcp/src/vm_service/vm_service_connector.dart';
import 'package:marionette_mcp/src/vm_service/vm_service_connector_contracts.dart';
import 'package:mcp_dart/mcp_dart.dart';

/// Registers read-only MCP tools that inspect the running app:
/// `get_interactive_elements`, `get_logs`, `take_screenshots`.
void registerInspectionTools(
  McpServer server,
  VmServiceConnector connector,
  logging.Logger logger,
) {
  server
    ..registerTool(
      'get_interactive_elements',
      description:
          'Returns a list of all interactive elements currently visible in the Flutter app UI tree. Each element includes its type, text content (if any), key (if any), and other identifying properties. This is useful for understanding what can be interacted with in the app. Requires an active connection established via connect.',
      annotations: const ToolAnnotations(
        title: 'Get Interactive Elements',
        readOnlyHint: true,
        idempotentHint: true,
      ),
      inputSchema: const ToolInputSchema(properties: {}),
      callback: (args, extra) async {
        logger.info('Getting interactive elements');
        return runTool(logger, 'get interactive elements', () async {
          final snapshot = await connector.getInteractiveElementSnapshot();

          final buffer = StringBuffer()
            ..writeln('Found ${snapshot.count} interactive element(s):\n');

          for (final element in snapshot.elements) {
            buffer.writeln(formatElement(element.toJson()));
          }

          return CallToolResult(
            content: [TextContent(text: buffer.toString())],
            structuredContent: snapshot.toJson(),
          );
        });
      },
    )
    ..registerTool(
      'capture',
      description:
          'Atomically saves a read-only UI checkpoint: elements.json, logs.json with cursor delta, and PNG screenshots. It never performs gestures or other UI actions. The output directory must not already exist.',
      annotations: const ToolAnnotations(
        title: 'Capture Read-Only Evidence',
        readOnlyHint: true,
        idempotentHint: false,
      ),
      inputSchema: ToolInputSchema(
        properties: {
          'output_dir': JsonSchema.string(
            description: 'New checkpoint evidence directory to publish.',
          ),
          'after_sequence': JsonSchema.number(
            description: 'Only include logs after this cursor.',
          ),
        },
        required: ['output_dir'],
      ),
      callback: (args, extra) async {
        logger.info('Capturing read-only evidence');
        return runTool(logger, 'capture read-only evidence', () async {
          final rawOutputDirectory = args['output_dir'];
          if (rawOutputDirectory is! String ||
              rawOutputDirectory.trim().isEmpty) {
            throw const ContractFormatException(
              'output_dir must be a non-empty string',
              path: 'output_dir',
            );
          }
          final rawAfterSequence = args['after_sequence'];
          if (rawAfterSequence != null && rawAfterSequence is! int) {
            throw const ContractFormatException(
              'after_sequence must be an integer',
              path: 'after_sequence',
            );
          }

          final elements = await connector.getInteractiveElementSnapshot();
          final logs = await connector.getLogSnapshot(
            afterSequence: rawAfterSequence as int?,
          );
          final screenshotResponse = await connector.takeScreenshots();
          final rawScreenshots = screenshotResponse['screenshots'];
          if (rawScreenshots is! List) {
            throw const ContractFormatException(
              'screenshots must be a list',
              path: 'screenshots',
            );
          }
          final screenshots = <String>[];
          for (var i = 0; i < rawScreenshots.length; i++) {
            final screenshot = rawScreenshots[i];
            if (screenshot is! String) {
              throw ContractFormatException(
                'screenshot must be a base64 string',
                path: 'screenshots[$i]',
              );
            }
            screenshots.add(screenshot);
          }

          final evidence = await publishCaptureEvidence(
            outputDirectory: rawOutputDirectory,
            elements: elements,
            logs: logs,
            screenshots: screenshots,
          );
          return CallToolResult(
            content: [
              TextContent(
                text: 'Capture saved to ${evidence.outputDirectory}\n'
                    '  elements.json (${elements.count} elements)\n'
                    '  logs.json (${logs.count} entries, cursor ${logs.cursor})\n'
                    '  screenshots/ (${evidence.screenshotPaths.length} image(s))',
              ),
            ],
            structuredContent: evidence.toJson(),
          );
        });
      },
    )
    ..registerTool(
      'get_logs',
      description:
          'Retrieves all application logs collected from the Flutter app since app start or since the last hot reload. This includes debug messages, errors, and other log output from the running app. Requires an active connection established via connect.',
      annotations: const ToolAnnotations(
        title: 'Get Application Logs',
        readOnlyHint: true,
      ),
      inputSchema: ToolInputSchema(
        properties: {
          'after_sequence': JsonSchema.number(
            description: 'Only return entries after this log sequence cursor.',
          ),
        },
      ),
      callback: (args, extra) async {
        logger.info('Getting application logs');

        try {
          final rawAfterSequence = args['after_sequence'];
          if (rawAfterSequence != null && rawAfterSequence is! int) {
            throw const ContractFormatException(
              'after_sequence must be an integer',
              path: 'after_sequence',
            );
          }
          final afterSequence = rawAfterSequence as int?;
          final snapshot = await connector.getLogSnapshot(
            afterSequence: afterSequence,
          );
          final logs = snapshot.legacyLogs;
          final count = snapshot.count;

          if (count == 0) {
            return CallToolResult(
              content: [const TextContent(text: 'No logs collected')],
              structuredContent: snapshot.toJson(),
            );
          }

          final buffer = StringBuffer()
            ..writeln(
              'Collected $count log entr${count == 1 ? 'y' : 'ies'}:\n',
            );

          for (final log in logs) {
            buffer.writeln(log);
          }

          return CallToolResult(
            content: [TextContent(text: buffer.toString())],
            structuredContent: snapshot.toJson(),
          );
        } on ContractFormatException catch (err) {
          logger.warning('Failed to get logs', err);
          return CallToolResult(
            isError: true,
            content: [TextContent(text: err.toString())],
            structuredContent:
                ContractFailure.fromException('get_logs', err).toJson(),
          );
        } on VmServiceExtensionException catch (err) {
          // Surface the VM service's own error message verbatim — it carries
          // setup instructions for enabling log collection.
          logger.warning('Failed to get logs', err);
          return CallToolResult(
            isError: true,
            content: [TextContent(text: err.error ?? err.message)],
          );
        } catch (err) {
          logger.warning('Failed to get logs', err);
          return CallToolResult(
            isError: true,
            content: [TextContent(text: err.toString())],
          );
        }
      },
    )
    ..registerTool(
      'take_screenshots',
      description:
          'Takes screenshots of all views in the Flutter app. Returns base64-encoded PNG images that can be decoded and saved. This captures the current visual state of the app. Requires an active connection established via connect.',
      annotations: const ToolAnnotations(
        title: 'Take Screenshots',
        readOnlyHint: true,
      ),
      inputSchema: const ToolInputSchema(properties: {}),
      callback: (args, extra) async {
        logger.info('Taking screenshots');
        return runTool(logger, 'take screenshots', () async {
          final response = await connector.takeScreenshots();
          final rawScreenshots = response['screenshots'];
          if (rawScreenshots is! List) {
            throw const ContractFormatException(
              'screenshots must be a list',
              path: 'screenshots',
            );
          }
          final screenshots = <String>[];
          for (var i = 0; i < rawScreenshots.length; i++) {
            final screenshot = rawScreenshots[i];
            if (screenshot is! String) {
              throw ContractFormatException(
                'screenshot must be a base64 string',
                path: 'screenshots[$i]',
              );
            }
            screenshots.add(screenshot);
          }

          if (screenshots.isEmpty) {
            return CallToolResult(
              content: [const TextContent(text: 'No screenshots captured')],
            );
          }
          return CallToolResult(
            content: screenshots
                .map(
                  (screenshot) =>
                      ImageContent(data: screenshot, mimeType: 'image/png'),
                )
                .toList(),
          );
        });
      },
    );
}
// @marionette-codec-boundary: explicit JSON/VM/MCP codec boundary
