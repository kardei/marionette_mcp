import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:marionette_flutter/src/binding/marionette_configuration.dart';
import 'package:marionette_flutter/src/services/widget_finder.dart';
import 'package:marionette_flutter/src/services/widget_matcher.dart';

/// Dispatches gesture events to simulate user interactions.
class GestureDispatcher {
  static const kMaxDelta = 40.0;
  static const kDelay = Duration(milliseconds: 10);

  static const _kDeviceId = 1;
  static const _kSecondDeviceId = 2;
  static const _kMouseDeviceId = 3;

  int _nextPointerId = 1;

  int get _viewId =>
      WidgetsBinding.instance.platformDispatcher.implicitView?.viewId ?? 0;

  PointerAddedEvent _added(Offset position,
          [int device = _kDeviceId,
          PointerDeviceKind kind = PointerDeviceKind.touch]) =>
      PointerAddedEvent(
          viewId: _viewId, position: position, kind: kind, device: device);

  PointerDownEvent _down(int pointer, Offset position,
          [int buttons = kPrimaryButton,
          int device = _kDeviceId,
          PointerDeviceKind kind = PointerDeviceKind.touch]) =>
      PointerDownEvent(
        viewId: _viewId,
        pointer: pointer,
        position: position,
        kind: kind,
        buttons: buttons,
        device: device,
      );

  PointerUpEvent _up(int pointer, Offset position,
          [int buttons = 0,
          int device = _kDeviceId,
          PointerDeviceKind kind = PointerDeviceKind.touch]) =>
      PointerUpEvent(
        viewId: _viewId,
        pointer: pointer,
        position: position,
        kind: kind,
        buttons: buttons,
        device: device,
      );

  PointerRemovedEvent _removed(Offset position,
          [int device = _kDeviceId,
          PointerDeviceKind kind = PointerDeviceKind.touch]) =>
      PointerRemovedEvent(
          viewId: _viewId, position: position, kind: kind, device: device);

  PointerMoveEvent _move(int pointer, Offset position,
          [Offset delta = Offset.zero,
          int device = _kDeviceId,
          PointerDeviceKind kind = PointerDeviceKind.touch]) =>
      PointerMoveEvent(
        viewId: _viewId,
        pointer: pointer,
        position: position,
        delta: delta,
        kind: kind,
        device: device,
      );

  /// Simulates a tap on an element that matches the given [matcher].
  ///
  /// If [matcher] is a [CoordinatesMatcher], taps directly at the specified
  /// coordinates without searching the widget tree (fast path).
  Future<void> tap(
    WidgetMatcher matcher,
    WidgetFinder widgetFinder,
    MarionetteConfiguration configuration,
  ) async {
    // Fast path for coordinate-based tapping
    if (matcher is CoordinatesMatcher) {
      await _dispatchTapAtPosition(matcher.offset);
      return;
    }

    final element = widgetFinder.findHittableElement(matcher, configuration);

    if (element == null) {
      throw Exception('Element matching ${matcher.toJson()} not found');
    } else {
      await _dispatchTapAtElement(element);
    }
  }

  Future<void> _dispatchTapAtElement(Element element) async {
    await _dispatchTapAtPosition(_globalCenterOf(element));
  }

  /// Returns the global position of the center of [element]'s [RenderBox].
  ///
  /// Throws if the element has no [RenderBox] or has not been laid out yet.
  Offset _globalCenterOf(Element element) {
    final renderObject = element.renderObject;

    if (renderObject is! RenderBox) {
      throw Exception('Element does not have a RenderBox');
    }

    if (!renderObject.hasSize) {
      throw Exception('RenderBox does not have a size yet');
    }

    final center = renderObject.size.center(Offset.zero);
    return renderObject.localToGlobal(center);
  }

  Future<void> _dispatchTapAtPosition(Offset globalPosition) async {
    final pointerId = _nextPointerId++;

    // Build the event records
    final records = [
      // Pointer down immediately
      [
        _added(globalPosition),
        _down(pointerId, globalPosition),
      ],
      // Pointer up after a short delay, then remove the device
      [
        _up(pointerId, globalPosition),
        _removed(globalPosition),
      ],
    ];

    await _handlePointerEventRecord(records);
  }

  /// Simulates a secondary (right mouse button) tap on an element matching
  /// [matcher].
  ///
  /// Dispatches a mouse pointer with [kSecondaryButton] pressed, which is what
  /// Flutter recognises as `onSecondaryTap` (e.g. context menus). Desktop only —
  /// touch devices do not support non-primary buttons.
  Future<void> secondaryTap(
    WidgetMatcher matcher,
    WidgetFinder widgetFinder,
    MarionetteConfiguration configuration,
  ) =>
      _mouseTap(matcher, widgetFinder, configuration,
          buttons: kSecondaryButton);

  Future<void> _mouseTap(
    WidgetMatcher matcher,
    WidgetFinder widgetFinder,
    MarionetteConfiguration configuration, {
    required int buttons,
  }) async {
    if (matcher is CoordinatesMatcher) {
      await _dispatchMouseTapAtPosition(matcher.offset, buttons);
      return;
    }

    final element = widgetFinder.findHittableElement(matcher, configuration);

    if (element == null) {
      throw Exception('Element matching ${matcher.toJson()} not found');
    }
    await _dispatchMouseTapAtPosition(_globalCenterOf(element), buttons);
  }

  Future<void> _dispatchMouseTapAtPosition(
    Offset globalPosition,
    int buttons,
  ) async {
    final pointerId = _nextPointerId++;

    final records = [
      // Mouse moves in and presses the requested button.
      [
        _added(globalPosition, _kMouseDeviceId, PointerDeviceKind.mouse),
        _down(pointerId, globalPosition, buttons, _kMouseDeviceId,
            PointerDeviceKind.mouse),
      ],
      // Button released (buttons: 0), then the device is removed.
      [
        _up(pointerId, globalPosition, 0, _kMouseDeviceId,
            PointerDeviceKind.mouse),
        _removed(globalPosition, _kMouseDeviceId, PointerDeviceKind.mouse),
      ],
    ];

    await _handlePointerEventRecord(records);
  }

  /// Simulates a double tap on an element that matches the given [matcher].
  ///
  /// Two taps are dispatched with [delay] between them.
  /// Defaults to 100ms, which is within Flutter's double-tap recognition
  /// window (kDoubleTapMinTime 40ms — kDoubleTapTimeout 300ms).
  Future<void> doubleTap(
    WidgetMatcher matcher,
    WidgetFinder widgetFinder,
    MarionetteConfiguration configuration, {
    Duration delay = const Duration(milliseconds: 100),
  }) async {
    if (delay.isNegative || delay == Duration.zero) {
      throw ArgumentError('delay must be positive');
    }

    if (matcher is CoordinatesMatcher) {
      await _dispatchDoubleTapAtPosition(matcher.offset, delay);
      return;
    }

    final element = widgetFinder.findHittableElement(matcher, configuration);

    if (element == null) {
      throw Exception('Element matching ${matcher.toJson()} not found');
    } else {
      await _dispatchDoubleTapAtElement(element, delay);
    }
  }

  Future<void> _dispatchDoubleTapAtElement(
    Element element,
    Duration delay,
  ) async {
    await _dispatchDoubleTapAtPosition(_globalCenterOf(element), delay);
  }

  Future<void> _dispatchDoubleTapAtPosition(
    Offset globalPosition,
    Duration delay,
  ) async {
    // First tap
    await _dispatchTapAtPosition(globalPosition);

    // Wait between taps for double-tap recognition
    await Future<void>.delayed(delay);

    // Second tap
    await _dispatchTapAtPosition(globalPosition);
  }

  /// Simulates a long press on an element that matches the given [matcher].
  ///
  /// The pointer is held down for [duration] before being released.
  /// Defaults to 600ms (kLongPressTimeout + kPressTimeout), matching
  /// Flutter's [WidgetTester.longPress] behavior.
  Future<void> longPress(
    WidgetMatcher matcher,
    WidgetFinder widgetFinder,
    MarionetteConfiguration configuration, {
    Duration duration = const Duration(milliseconds: 600),
  }) async {
    if (duration.isNegative || duration == Duration.zero) {
      throw ArgumentError('duration must be positive');
    }

    if (matcher is CoordinatesMatcher) {
      await _dispatchLongPressAtPosition(matcher.offset, duration);
      return;
    }

    final element = widgetFinder.findHittableElement(matcher, configuration);

    if (element == null) {
      throw Exception('Element matching ${matcher.toJson()} not found');
    } else {
      await _dispatchLongPressAtElement(element, duration);
    }
  }

  Future<void> _dispatchLongPressAtElement(
    Element element,
    Duration duration,
  ) async {
    await _dispatchLongPressAtPosition(_globalCenterOf(element), duration);
  }

  Future<void> _dispatchLongPressAtPosition(
    Offset globalPosition,
    Duration duration,
  ) async {
    final pointerId = _nextPointerId++;

    final records = [
      [
        _added(globalPosition),
        _down(pointerId, globalPosition),
      ],
    ];

    // Dispatch pointer down
    await _handlePointerEventRecord(records);

    // Hold for the specified duration to trigger long press recognition
    await Future<void>.delayed(duration);

    // Release
    await _handlePointerEventRecord([
      [
        _up(pointerId, globalPosition),
        _removed(globalPosition),
      ],
    ]);
  }

  /// Simulates a swipe gesture on an element matching [matcher] in the given
  /// [direction] for [distance] pixels.
  ///
  /// The swipe starts from the center of the matched element and moves in the
  /// specified direction.
  Future<void> swipe(
    WidgetMatcher matcher,
    WidgetFinder widgetFinder,
    MarionetteConfiguration configuration, {
    required String direction,
    double distance = 200.0,
  }) async {
    final element = widgetFinder.findElement(matcher, configuration);

    if (element == null) {
      throw Exception('Element matching ${matcher.toJson()} not found');
    }

    final start = _globalCenterOf(element);

    final end = switch (direction) {
      'left' => start + Offset(-distance, 0),
      'right' => start + Offset(distance, 0),
      'up' => start + Offset(0, -distance),
      'down' => start + Offset(0, distance),
      _ => throw ArgumentError('Invalid direction: $direction. '
          'Must be one of: left, right, up, down'),
    };

    await drag(start, end);
  }

  /// Simulates a pinch zoom gesture centered on an element matching [matcher].
  ///
  /// [scale] controls the zoom:
  /// - scale > 1.0: zoom in (fingers move apart)
  /// - scale < 1.0: zoom out (fingers move together)
  ///
  /// [startDistance] is the initial distance between the two fingers in pixels.
  Future<void> pinchZoom(
    WidgetMatcher matcher,
    WidgetFinder widgetFinder,
    MarionetteConfiguration configuration, {
    required double scale,
    double startDistance = 200.0,
  }) async {
    if (scale <= 0) {
      throw ArgumentError('scale must be positive');
    }
    if (startDistance <= 0) {
      throw ArgumentError('startDistance must be positive');
    }

    if (matcher is CoordinatesMatcher) {
      await _dispatchPinchZoomAtPosition(
        matcher.offset,
        scale: scale,
        startDistance: startDistance,
      );
      return;
    }

    final element = widgetFinder.findHittableElement(matcher, configuration);

    if (element == null) {
      throw Exception('Element matching ${matcher.toJson()} not found');
    }

    final globalCenter = _globalCenterOf(element);

    await _dispatchPinchZoomAtPosition(
      globalCenter,
      scale: scale,
      startDistance: startDistance,
    );
  }

  Future<void> _dispatchPinchZoomAtPosition(
    Offset center, {
    required double scale,
    required double startDistance,
  }) async {
    final pointer1Id = _nextPointerId++;
    final pointer2Id = _nextPointerId++;
    final endDistance = startDistance * scale;

    const stepCount = 10;

    // Finger positions: horizontally offset from center
    Offset finger1(double distance) => center - Offset(distance / 2, 0);
    Offset finger2(double distance) => center + Offset(distance / 2, 0);

    final start1 = finger1(startDistance);
    final start2 = finger2(startDistance);

    // Phase 1: Both fingers down
    final records = <List<PointerEvent>>[
      [
        _added(start1),
        _down(pointer1Id, start1),
      ],
      [
        _added(start2, _kSecondDeviceId),
        _down(pointer2Id, start2, 0, _kSecondDeviceId),
      ],
    ];

    // Phase 2: Move fingers apart (zoom in) or together (zoom out)
    for (var i = 1; i <= stepCount; i++) {
      final t = i / stepCount;
      final currentDistance = startDistance + (endDistance - startDistance) * t;
      final pos1 = finger1(currentDistance);
      final pos2 = finger2(currentDistance);

      records.add([
        _move(pointer1Id, pos1),
        _move(pointer2Id, pos2, Offset.zero, _kSecondDeviceId),
      ]);
    }

    // Phase 3: Both fingers up
    final end1 = finger1(endDistance);
    final end2 = finger2(endDistance);

    records.addAll([
      [
        _up(pointer1Id, end1),
        _up(pointer2Id, end2, 0, _kSecondDeviceId),
      ],
      [
        _removed(end1),
        _removed(end2, _kSecondDeviceId),
      ],
    ]);

    await _handlePointerEventRecord(records);
  }

  /// Simulates a drag gesture from [from] to [to].
  Future<void> drag(Offset from, Offset to) async {
    final pointerId = _nextPointerId++;

    final delta = to - from;
    final distance = delta.distance;
    final stepCount =
        (distance / kMaxDelta).ceil().clamp(1, double.infinity).toInt();

    final moveRecords = <List<PointerEvent>>[];
    for (var i = 1; i <= stepCount; i++) {
      final t = i / stepCount;
      final position = Offset.lerp(from, to, t)!;
      final previousPosition =
          i == 1 ? from : Offset.lerp(from, to, (i - 1) / stepCount)!;
      final stepDelta = position - previousPosition;

      moveRecords.add([
        _move(pointerId, position, stepDelta),
      ]);
    }

    final records = [
      [
        _added(from),
        _down(pointerId, from),
      ],
      ...moveRecords,
      [
        _up(pointerId, to),
        _removed(to),
      ],
    ];

    await _handlePointerEventRecord(records);
  }

  /// Handles a list of pointer event records by dispatching them with proper timing.
  ///
  /// Similar to Flutter's test framework handlePointerEventRecord, but simplified
  /// for live app execution.
  Future<void> _handlePointerEventRecord(
    List<List<PointerEvent>> records,
  ) async {
    for (final record in records) {
      record.forEach(GestureBinding.instance.handlePointerEvent);
      WidgetsBinding.instance.scheduleFrame();
      await Future<void>.delayed(kDelay);
    }
  }
}
