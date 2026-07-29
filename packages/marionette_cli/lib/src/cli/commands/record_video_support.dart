import 'dart:io';

import 'package:marionette_cli/src/cli/adb_helper.dart';
import 'package:marionette_mcp/src/video/ffmpeg_process.dart';
import 'package:marionette_mcp/src/video/recording_session.dart';
import 'package:marionette_mcp/src/video/tcp_frame_reader.dart';
import 'package:marionette_mcp/src/video/video_options.dart';
import 'package:marionette_mcp/src/video/video_recorder.dart';
import 'package:marionette_mcp/src/video/ws_frame_server.dart';
import 'package:marionette_mcp/src/vm_service/vm_service_connector.dart';

typedef FfmpegAvailabilityChecker = Future<bool> Function({String ffmpegPath});

typedef RecordingSessionFactory = Future<RecordingSession> Function({
  required int frameServerPort,
  required String outputFile,
  required int width,
  required int height,
  required String ffmpegPath,
});

typedef WsRecordingSessionFactory = Future<RecordingSession> Function({
  required FrameSource frameSource,
  required String outputFile,
  required int width,
  required int height,
  required String ffmpegPath,
});

typedef WsFrameServerFactory = Future<WebSocketFrameServer> Function();
typedef OpenCommand = ({String executable, List<String> args});
typedef OpenCommandResolver = OpenCommand? Function();
typedef AdbHelperFactory = AdbHelper Function();

Future<ReverseWsResult> startReverseWsSession({
  required VmServiceConnector connector,
  required ({int width, int height})? effectiveSize,
  required ({int width, int height}) videoSize,
  required String outputPath,
  required String ffmpegPath,
  required WsFrameServerFactory wsFrameServerFactory,
  required WsRecordingSessionFactory wsSessionFactory,
  required AdbHelperFactory adbHelperFactory,
}) async {
  final adb = adbHelperFactory();
  if (!await adb.isAvailable()) {
    stderr.writeln(
      "Error: 'adb' not found on PATH. The Android device's frame port is "
      'not directly reachable from the host, so adb is needed to set up a '
      'reverse tunnel. Add the Android SDK platform-tools to your PATH, or '
      'specify --transport tcp with manual port forwarding.',
    );
    throw AdbFallbackException();
  }

  final wsServer = await wsFrameServerFactory();
  final adbResult = await adb.setupReverse(wsServer.port);
  if (!adbResult.success) {
    await wsServer.close();
    stderr.writeln(
      "Error: 'adb reverse' failed: ${adbResult.stderr}. Make sure a single "
      "device is connected (use 'adb devices' to check), or specify "
      "--transport tcp and forward the frame port manually with "
      "'adb forward tcp:PORT tcp:PORT'.",
    );
    throw AdbFallbackException();
  }

  try {
    await connector.stopScreencast();
    await connector.startScreencast(
      maxWidth: effectiveSize?.width,
      maxHeight: effectiveSize?.height,
      wsPort: wsServer.port,
    );
    final session = await wsSessionFactory(
      frameSource: wsServer,
      outputFile: outputPath,
      width: videoSize.width,
      height: videoSize.height,
      ffmpegPath: ffmpegPath,
    );
    return ReverseWsResult(session: session, adbReversePort: wsServer.port);
  } catch (_) {
    await wsServer.close();
    await cleanupAdbReverse(wsServer.port, adbHelperFactory);
    rethrow;
  }
}

Future<void> cleanupAdbReverse(
    int? port, AdbHelperFactory adbHelperFactory) async {
  if (port == null) return;
  try {
    await adbHelperFactory().removeReverse(port);
  } catch (_) {
    // Best effort cleanup must not mask the original recording error.
  }
}

void cleanupRecordingOutputFile(String path) {
  try {
    final file = File(path);
    if (file.existsSync()) file.deleteSync();
  } catch (_) {
    // Best effort cleanup must not mask the original recording error.
  }
}

Future<RecordingSession> defaultSessionFactory({
  required int frameServerPort,
  required String outputFile,
  required int width,
  required int height,
  required String ffmpegPath,
}) async {
  final frameReader = TcpFrameReader(host: 'localhost', port: frameServerPort);
  await frameReader.connect();
  return buildRecordingSession(
    frameSource: frameReader,
    outputFile: outputFile,
    width: width,
    height: height,
    ffmpegPath: ffmpegPath,
  );
}

Future<RecordingSession> defaultWsSessionFactory({
  required FrameSource frameSource,
  required String outputFile,
  required int width,
  required int height,
  required String ffmpegPath,
}) =>
    buildRecordingSession(
      frameSource: frameSource,
      outputFile: outputFile,
      width: width,
      height: height,
      ffmpegPath: ffmpegPath,
    );

Future<RecordingSession> buildRecordingSession({
  required FrameSource frameSource,
  required String outputFile,
  required int width,
  required int height,
  required String ffmpegPath,
}) async {
  final options = VideoOptions(
    width: width,
    height: height,
    outputFile: outputFile,
  );
  final ffmpeg = await FfmpegProcess.start(
    options: options,
    ffmpegPath: ffmpegPath,
  );
  final recorder = VideoRecorder(
    VideoRecorderOptions(fps: options.fps, width: width, height: height),
    ffmpeg,
  );
  return RecordingSession(
    frameSource: frameSource,
    videoRecorder: recorder,
    ffmpegCloseable: ffmpeg,
    outputFile: outputFile,
  );
}

OpenCommand? defaultOpenCommand() {
  if (Platform.isLinux) return (executable: 'xdg-open', args: <String>[]);
  if (Platform.isMacOS) return (executable: 'open', args: <String>[]);
  if (Platform.isWindows) {
    return (executable: 'cmd', args: ['/c', 'start', '']);
  }
  return null;
}

class ReverseWsResult {
  ReverseWsResult({required this.session, required this.adbReversePort});
  final RecordingSession session;
  final int adbReversePort;
}

class AdbFallbackException implements Exception {}
