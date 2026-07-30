import 'package:flutter/scheduler.dart';

const _frameGrace = Duration(milliseconds: 50);
const _frameInterval = Duration(milliseconds: 16);
const _maxFramePulses = 60;

/// Falls back to framework-driven frames when a hidden Web page stops
/// delivering requestAnimationFrame callbacks.
Future<void> settleStarvedFrames() async {
  final binding = SchedulerBinding.instance;
  if (!binding.hasScheduledFrame) return;

  var observedTimestamp = binding.currentSystemFrameTimeStamp;
  await Future<void>.delayed(_frameGrace);

  if (!binding.hasScheduledFrame ||
      binding.currentSystemFrameTimeStamp != observedTimestamp) {
    return;
  }

  for (var pulse = 0; pulse < _maxFramePulses; pulse++) {
    if (!binding.hasScheduledFrame && binding.transientCallbackCount == 0) {
      return;
    }

    await Future<void>.delayed(_frameInterval);

    // A real engine frame resumed while waiting, so it owns the lifecycle.
    if (binding.currentSystemFrameTimeStamp != observedTimestamp) return;
    if (binding.schedulerPhase != SchedulerPhase.idle) continue;

    observedTimestamp += _frameInterval;
    binding.handleBeginFrame(observedTimestamp);
    binding.handleDrawFrame();
  }
}
