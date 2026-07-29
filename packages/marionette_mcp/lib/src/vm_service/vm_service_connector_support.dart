import 'package:logging/logging.dart' as logging;
import 'package:vm_service/vm_service.dart';

/// Exception thrown when an operation is attempted without an active connection.
class NotConnectedException implements Exception {
  const NotConnectedException();

  @override
  String toString() =>
      'Not connected to any app. Use app.connect tool first with the VM service URI.';
}

/// Exception thrown when a VM service extension call fails.
class VmServiceExtensionException implements Exception {
  VmServiceExtensionException(
    this.message, {
    this.errorCode,
    this.error,
    this.stackTrace,
  });

  final String message;
  final int? errorCode;
  final String? error;
  final String? stackTrace;

  @override
  String toString() {
    final buffer = StringBuffer(message);
    if (error != null) {
      buffer.write('\nError: $error');
    }
    if (stackTrace != null) {
      buffer.write('\nStack trace: $stackTrace');
    }
    return buffer.toString();
  }
}

/// Modifier keys accepted by [VmServiceConnector.pressKey].
const supportedKeyModifiers = {'control', 'shift', 'alt', 'meta'};

/// Validates a comma-separated modifier list.
String? invalidModifiersError(String? modifiers) {
  if (modifiers == null || modifiers.trim().isEmpty) return null;
  final invalid = modifiers
      .split(',')
      .map((modifier) => modifier.trim())
      .where((modifier) => modifier.isNotEmpty)
      .where(
          (modifier) => !supportedKeyModifiers.contains(modifier.toLowerCase()))
      .toList();
  if (invalid.isEmpty) return null;
  final plural = invalid.length > 1 ? 's' : '';
  return 'Unsupported modifier$plural: ${invalid.join(', ')}. '
      'Supported modifiers: ${supportedKeyModifiers.join(', ')}.';
}

/// Finds an isolate exposing Marionette's informational extension.
Future<String> findMarionetteIsolate(
  VmService service,
  logging.Logger logger, {
  int attempts = 1,
  Duration delay = const Duration(milliseconds: 500),
}) async {
  for (var attempt = 0; attempt < attempts; attempt++) {
    if (attempt > 0) {
      await Future<void>.delayed(delay);
    }

    final vm = await service.getVM();
    if (vm.isolates == null || vm.isolates!.isEmpty) {
      continue;
    }

    for (final isolateRef in vm.isolates!) {
      if (isolateRef.id == null) {
        continue;
      }

      try {
        final isolate = await service.getIsolate(isolateRef.id!);
        final hasExtension = isolate.extensionRPCs?.any(
              (ext) => ext == 'ext.flutter.marionette.getLogs',
            ) ??
            false;

        if (hasExtension) {
          return isolateRef.id!;
        }
      } catch (error) {
        logger.warning(
          'Failed to check extensions for isolate ${isolateRef.id}',
          error,
        );
      }
    }
  }

  throw Exception(
    'No isolate found with ext.flutter.marionette.getLogs extension. '
    'Make sure the Flutter app has marionette_flutter initialized.',
  );
}
