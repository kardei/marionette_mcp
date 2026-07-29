import 'dart:async';
import 'dart:io';

import 'package:marionette_cli/src/cli/adb_helper.dart';
import 'package:marionette_cli/src/cli/instance_command.dart';
import 'package:marionette_cli/src/instance_registry.dart';
import 'package:marionette_mcp/src/video/ffmpeg_process.dart';
import 'package:marionette_mcp/src/video/recording_session.dart';
import 'package:marionette_mcp/src/video/video_options.dart';
import 'package:marionette_mcp/src/video/ws_frame_server.dart';
import 'package:marionette_mcp/src/vm_service/vm_service_connector.dart';
import 'package:marionette_cli/src/cli/commands/record_video_support.dart';

export 'record_video_support.dart';

/// Records a video of a running Flutter app via the screencast pipeline.
class RecordVideoCommand extends InstanceCommand {
  RecordVideoCommand(
    this._registry, {
    FfmpegAvailabilityChecker? ffmpegChecker,
    RecordingSessionFactory? sessionFactory,
    WsRecordingSessionFactory? wsSessionFactory,
    WsFrameServerFactory? wsFrameServerFactory,
    OpenCommandResolver? openCommandResolver,
    AdbHelperFactory? adbHelperFactory,
  })  : _ffmpegChecker = ffmpegChecker ?? FfmpegProcess.isAvailable,
        _sessionFactory = sessionFactory ?? defaultSessionFactory,
        _wsSessionFactory = wsSessionFactory ?? defaultWsSessionFactory,
        _wsFrameServerFactory =
            wsFrameServerFactory ?? WebSocketFrameServer.bind,
        _openCommandResolver = openCommandResolver ?? defaultOpenCommand,
        _adbHelperFactory = adbHelperFactory ?? AdbHelper.new {
    argParser
      ..addOption(
        'output',
        abbr: 'o',
        help: 'Output file path for the video. Must end with .webm.',
        mandatory: true,
      )
      ..addFlag(
        'open',
        help: 'Open the video after recording.',
        defaultsTo: false,
      )
      ..addOption(
        'duration',
        abbr: 'd',
        help: 'Recording duration in seconds. Records until Ctrl+C if not set.',
      )
      ..addOption(
        'width',
        help: 'Video width in pixels. Must not exceed the viewport width.\n'
            'Default: native viewport (native) or 1280 (web).',
      )
      ..addOption(
        'height',
        help: 'Video height in pixels. Must not exceed the viewport height.\n'
            'Default: native viewport (native) or 720 (web).',
      )
      ..addOption(
        'ffmpeg-path',
        help: 'Path to ffmpeg binary.',
        defaultsTo: 'ffmpeg',
      )
      ..addFlag(
        'verbose',
        abbr: 'v',
        help: 'Print diagnostic details (probe response, frame counts).',
        defaultsTo: false,
      )
      ..addOption(
        'transport',
        help: 'Frame transport mode.\n'
            '  auto: try TCP, fall back to reverse-WS via adb (default)\n'
            '  tcp:  force TCP (fail if unreachable)\n'
            '  ws:   force reverse-WS (requires adb)',
        defaultsTo: 'auto',
        allowed: ['auto', 'tcp', 'ws'],
      )
      ..addOption(
        'frame-port',
        help: 'Use a specific TCP port for frame streaming instead of\n'
            'auto-negotiation. Useful when adb reverse is unavailable.\n'
            'Example: adb forward tcp:9999 tcp:<flutter-port>',
      );
  }

  final InstanceRegistry _registry;
  final FfmpegAvailabilityChecker _ffmpegChecker;
  final RecordingSessionFactory _sessionFactory;
  final WsRecordingSessionFactory _wsSessionFactory;
  final WsFrameServerFactory _wsFrameServerFactory;
  final OpenCommandResolver _openCommandResolver;
  final AdbHelperFactory _adbHelperFactory;

  @override
  InstanceRegistry get registry => _registry;

  @override
  String get name => 'record-video';

  @override
  String get description => 'Record a video of the running Flutter app.';

  @override
  Future<int> execute(VmServiceConnector connector) async {
    final outputPath = argResults!['output'] as String;
    final ffmpegPath = argResults!['ffmpeg-path'] as String;
    final durationStr = argResults!['duration'] as String?;
    final widthStr = argResults!['width'] as String?;
    final heightStr = argResults!['height'] as String?;
    final shouldOpen = argResults!['open'] as bool;
    final verbose = argResults!['verbose'] as bool;

    if (!outputPath.endsWith('.webm')) {
      stderr.writeln('Error: Output file must end with .webm');
      return 1;
    }

    final transport = argResults!['transport'] as String;
    final framePortStr = argResults!['frame-port'] as String?;

    if (framePortStr != null && transport == 'ws') {
      stderr.writeln(
        'Error: --frame-port and --transport ws are mutually exclusive',
      );
      return 1;
    }

    int? framePort;
    if (framePortStr != null) {
      framePort = int.tryParse(framePortStr);
      if (framePort == null || framePort <= 0) {
        stderr.writeln('Error: --frame-port must be a positive integer');
        return 1;
      }
    }

    if ((widthStr == null) != (heightStr == null)) {
      stderr.writeln('Error: --width and --height must be specified together');
      return 1;
    }

    ({int width, int height})? explicitSize;
    if (widthStr != null && heightStr != null) {
      final w = int.tryParse(widthStr);
      final h = int.tryParse(heightStr);
      if (w == null) {
        stderr.writeln('Error: --width must be a valid integer');
        return 1;
      }
      if (h == null) {
        stderr.writeln('Error: --height must be a valid integer');
        return 1;
      }
      if (w <= 0 || h <= 0) {
        stderr.writeln('Error: --width and --height must be positive integers');
        return 1;
      }
      explicitSize = (width: w, height: h);
    }

    int? durationSeconds;
    if (durationStr != null) {
      durationSeconds = int.tryParse(durationStr);
      if (durationSeconds == null || durationSeconds <= 0) {
        stderr.writeln('Error: --duration must be a positive integer');
        return 1;
      }
    }

    if (!await _ffmpegChecker(ffmpegPath: ffmpegPath)) {
      stderr.writeln(
        'Error: ffmpeg not found at "$ffmpegPath".\n'
        'Install ffmpeg:\n'
        '  macOS:   brew install ffmpeg\n'
        '  Ubuntu:  sudo apt install ffmpeg\n'
        '  Windows: winget install ffmpeg',
      );
      return 1;
    }

    File(outputPath).parent.createSync(recursive: true);

    // Start the screencast. For TCP transport (native), the Flutter app opens
    // a TCP server and returns the port. For WS transport (web), the MCP side
    // starts a WebSocket server and passes the port to the Flutter app.
    stdout.writeln('Starting screencast...');

    // Probe to determine transport and frame dimensions.
    // When explicit size is given, send it as a bounding-box constraint.
    // Otherwise send no constraint so Flutter captures at native viewport
    // resolution (auto mode — native uses full viewport, web is capped below).
    final probeResponse = await connector.startScreencast(
      maxWidth: explicitSize?.width,
      maxHeight: explicitSize?.height,
    );
    final deviceTransport = (probeResponse['transport'] as String?) ?? 'tcp';

    // For web auto mode, apply a safe default cap. Flutter's CPU-only web
    // renderer hangs on toImage above ~1.3M pixels. 1280x720 (0.92M) is
    // well within the safe range.
    final effectiveSize = explicitSize ??
        (deviceTransport == 'ws'
            ? (width: webDefaultMaxWidth, height: webDefaultMaxHeight)
            : null);

    // If the probe used different constraints than we'll actually record
    // with (web auto mode), re-probe to get correct frame dimensions.
    Map<String, dynamic> response;
    if (effectiveSize != null &&
        explicitSize == null &&
        deviceTransport == 'ws') {
      response = await connector.startScreencast(
        maxWidth: effectiveSize.width,
        maxHeight: effectiveSize.height,
      );
    } else {
      response = probeResponse;
    }

    if (verbose) {
      final viewportW = response['viewportWidth'];
      final viewportH = response['viewportHeight'];
      final frameW = response['frameWidth'];
      final frameH = response['frameHeight'];
      stderr.writeln(
        '[verbose] Probe response: transport=$deviceTransport, '
        'viewport=${viewportW}x$viewportH, '
        'frame=${frameW}x$frameH, '
        'requested=${explicitSize != null ? "${explicitSize.width}x${explicitSize.height}" : "auto"}',
      );
    }

    // Fail fast if explicit dimensions exceed the viewport. The Flutter side
    // cannot upscale beyond the viewport and silently produces 0 frames.
    if (explicitSize != null && response.containsKey('viewportWidth')) {
      final viewportW = response['viewportWidth'] as int;
      final viewportH = response['viewportHeight'] as int;
      if (explicitSize.width > viewportW || explicitSize.height > viewportH) {
        // Clean up the probe's screencast before exiting.
        if (deviceTransport != 'ws') {
          await connector.stopScreencast();
        }
        stderr.writeln(
          'Error: Requested ${explicitSize.width}x${explicitSize.height} '
          'exceeds the Flutter viewport (${viewportW}x$viewportH).\n'
          'The viewport is the maximum recordable resolution.\n'
          'Either use --width $viewportW --height $viewportH, '
          'or omit --width/--height to record at native viewport size.',
        );
        return 1;
      }
    }

    // The Flutter side computes the actual frame dimensions via
    // computeFrameSize and returns them. Use these as the single source
    // of truth so ffmpeg's expected dimensions always match the frames.
    final ({int width, int height}) videoSize;
    if (response.containsKey('frameWidth')) {
      videoSize = (
        width: response['frameWidth'] as int,
        height: response['frameHeight'] as int,
      );
    } else {
      // Fallback for older Flutter-side versions that don't report frame dims.
      videoSize = effectiveSize != null
          ? validateVideoSize(size: effectiveSize)
          : validateVideoSize(
              viewportSize: (
                width: response['viewportWidth'] as int,
                height: response['viewportHeight'] as int,
              ),
            );
    }

    // For TCP, the probe actually started a screencast — stop it before
    // restarting with computed dimensions. For WS, the probe was a no-op.
    if (effectiveSize == null && deviceTransport != 'ws') {
      await connector.stopScreencast();
    }

    int? adbReversePort;
    try {
      RecordingSession session;
      if (transport == 'ws') {
        // Force WS: skip TCP, go straight to reverse-WS.
        final result = await _startReverseWsSession(
          connector: connector,
          effectiveSize: effectiveSize,
          videoSize: videoSize,
          outputPath: outputPath,
          ffmpegPath: ffmpegPath,
        );
        session = result.session;
        adbReversePort = result.adbReversePort;
      } else if (framePort != null) {
        // Explicit frame port: connect directly, no fallback.
        session = await _sessionFactory(
          frameServerPort: framePort,
          outputFile: outputPath,
          width: videoSize.width,
          height: videoSize.height,
          ffmpegPath: ffmpegPath,
        );
      } else if (deviceTransport == 'ws') {
        // Web transport: MCP hosts the WebSocket server. The probe call
        // returned transport info without actually starting the screencast,
        // so we just need one real startScreencast with wsPort.
        final wsServer = await _wsFrameServerFactory();
        await connector.startScreencast(
          maxWidth: effectiveSize?.width,
          maxHeight: effectiveSize?.height,
          wsPort: wsServer.port,
        );
        session = await _wsSessionFactory(
          frameSource: wsServer,
          outputFile: outputPath,
          width: videoSize.width,
          height: videoSize.height,
          ffmpegPath: ffmpegPath,
        );
      } else {
        // Auto or forced TCP: try TCP first.
        //
        // Keep a reference to the factory future outside the try block so the
        // catch handler can register an orphan-cleanup callback on it.  Dart
        // futures cannot be cancelled; if the 2-second timeout fires while
        // socket.connect() is still in progress, the future continues running
        // in the background. Without cleanup it could eventually spawn an
        // ffmpeg process that never receives frames and never terminates.
        Future<RecordingSession>? pendingSession;
        try {
          // TCP transport: Flutter app hosts the TCP server.
          // When explicit size was given, the probe already started the
          // screencast with the right constraints — reuse its port.
          // Otherwise the probe was stopped earlier, so start fresh.
          final int frameServerPort;
          if (explicitSize != null) {
            frameServerPort = probeResponse['port'] as int;
          } else {
            final tcpResponse = await connector.startScreencast();
            frameServerPort = tcpResponse['port'] as int;
          }
          pendingSession = _sessionFactory(
            frameServerPort: frameServerPort,
            outputFile: outputPath,
            width: videoSize.width,
            height: videoSize.height,
            ffmpegPath: ffmpegPath,
          );
          session = await pendingSession.timeout(const Duration(seconds: 2));
        } on Exception {
          // Register a cleanup on the orphaned future: if it eventually
          // completes, stop() closes the TcpFrameReader socket and terminates
          // the ffmpeg process so no resources are leaked.  The immediately-
          // invoked async absorbs both factory errors and stop() errors so
          // neither leaks into the zone as an unhandled exception.
          if (pendingSession != null) {
            // ignore: discarded_futures
            () async {
              try {
                final s = await pendingSession!;
                await s.stop();
              } catch (_) {}
            }();
          }
          if (transport == 'tcp') {
            try {
              await connector.stopScreencast();
            } catch (_) {}
            stderr.writeln(
              'Error: TCP frame connection failed. The device frame port is '
              'not reachable from the host. If recording an Android device, '
              'use --transport auto to enable adb reverse fallback, or '
              'manually forward the port with '
              "'adb forward tcp:PORT tcp:PORT'.",
            );
            return 1;
          }
          // Auto mode: fall back to reverse-WS.
          final result = await _startReverseWsSession(
            connector: connector,
            effectiveSize: effectiveSize,
            videoSize: videoSize,
            outputPath: outputPath,
            ffmpegPath: ffmpegPath,
          );
          session = result.session;
          adbReversePort = result.adbReversePort;
        }
      }

      stdout.writeln(
        'Recording ${videoSize.width}x${videoSize.height} video to $outputPath...',
      );

      session.start();

      final completer = Completer<void>();
      Timer? durationTimer;

      if (durationSeconds != null) {
        durationTimer = Timer(Duration(seconds: durationSeconds), () {
          if (!completer.isCompleted) completer.complete();
        });
      }

      final sigintSub = ProcessSignal.sigint.watch().listen((_) {
        if (!completer.isCompleted) completer.complete();
      });

      stdout.writeln('Press Ctrl+C to stop recording.');
      await completer.future;
      durationTimer?.cancel();
      await sigintSub.cancel();

      try {
        await connector.stopScreencast();
      } catch (_) {
        // Best-effort — continue to finalize the local recording even if the
        // VM connection is gone (e.g., the app crashed during recording).
      }

      final RecordingResult result;
      try {
        result = await session.stop();
      } on Exception catch (e) {
        stderr.writeln('Error: Recording failed during finalization: $e');
        cleanupRecordingOutputFile(outputPath);
        return 1;
      } finally {
        // Second call is a no-op on the Flutter side (isActive is already
        // false); kept as a safety net in case the early call above failed.
        try {
          await connector.stopScreencast();
        } catch (_) {}
        await cleanupAdbReverse(adbReversePort, _adbHelperFactory);
      }
      stdout.writeln(
        'Recording complete: ${result.outputFile} '
        '(${result.duration.inSeconds}s, ${result.frameCount} frames)',
      );

      if (result.frameCount == 0 && verbose) {
        stderr.writeln(
          '[verbose] 0 frames received. Possible causes:\n'
          '  - Capture size too close to viewport (try smaller --width/--height)\n'
          '  - Flutter app not rendering (check debug console for errors)\n'
          '  - Frame capturer returning null (check Flutter debug output)',
        );
      }

      if (shouldOpen) {
        final command = _openCommandResolver();
        if (command != null) {
          await Process.run(command.executable, [...command.args, outputPath]);
        } else {
          stderr.writeln('Warning: --open is not supported on this platform.');
        }
      }

      return 0;
    } on AdbFallbackException {
      // Error already printed by _startReverseWsSession.
      try {
        await connector.stopScreencast();
      } catch (_) {}
      return 1;
    } catch (e) {
      try {
        await connector.stopScreencast();
      } catch (_) {
        // Don't mask the original error with a cleanup failure.
      }
      await cleanupAdbReverse(adbReversePort, _adbHelperFactory);
      rethrow;
    }
  }

  Future<ReverseWsResult> _startReverseWsSession({
    required VmServiceConnector connector,
    required ({int width, int height})? effectiveSize,
    required ({int width, int height}) videoSize,
    required String outputPath,
    required String ffmpegPath,
  }) async {
    return startReverseWsSession(
      connector: connector,
      effectiveSize: effectiveSize,
      videoSize: videoSize,
      outputPath: outputPath,
      ffmpegPath: ffmpegPath,
      wsFrameServerFactory: _wsFrameServerFactory,
      wsSessionFactory: _wsSessionFactory,
      adbHelperFactory: _adbHelperFactory,
    );
  }
}
// @marionette-codec-boundary: explicit JSON/VM/MCP codec boundary
