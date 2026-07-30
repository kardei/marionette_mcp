import 'package:marionette_flutter/src/services/frame_settler_stub.dart'
    if (dart.library.js_interop) 'package:marionette_flutter/src/services/frame_settler_web.dart'
    as implementation;

/// Advances Flutter frames only when a Web frame request is demonstrably
/// starved. Native platforms do not need this fallback.
Future<void> settleStarvedFrames() => implementation.settleStarvedFrames();
