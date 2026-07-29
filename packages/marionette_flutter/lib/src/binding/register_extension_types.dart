import 'package:marionette_flutter/src/binding/marionette_extension_result.dart';

/// Callback type for Marionette extension handlers.
typedef MarionetteExtensionCallback = Future<MarionetteExtensionResult>
    Function(Map<String, String> params);
