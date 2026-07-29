// @marionette-codec-boundary: explicit JSON/VM/MCP codec boundary
part of marionette_contracts;

/// Machine-readable connection state shared by MCP and CLI consumers.
class ConnectionInfo {
  const ConnectionInfo({
    required this.connected,
    this.uri,
    this.isolateId,
    this.bindingVersion,
    this.connectedAt,
    this.error,
  });

  const ConnectionInfo.connected({
    required String uri,
    String? isolateId,
    String? bindingVersion,
    DateTime? connectedAt,
  }) : this(
          connected: true,
          uri: uri,
          isolateId: isolateId,
          bindingVersion: bindingVersion,
          connectedAt: connectedAt,
        );

  const ConnectionInfo.disconnected({String? uri, String? error})
      : this(connected: false, uri: uri, error: error);

  factory ConnectionInfo.fromJson(Map<String, dynamic> json) {
    _validateVersions(json);
    final connected = _requiredBool(json, 'connected');
    final uri = _optionalString(json, 'uri');
    if (connected && uri == null) {
      _invalid('uri', 'is required when connected is true');
    }
    return ConnectionInfo(
      connected: connected,
      uri: uri,
      isolateId: _optionalString(json, 'isolateId'),
      bindingVersion: _optionalString(json, 'bindingVersion'),
      connectedAt: _optionalTime(json, 'connectedAt'),
      error: _optionalString(json, 'error'),
    );
  }

  final bool connected;
  final String? uri;
  final String? isolateId;
  final String? bindingVersion;
  final DateTime? connectedAt;
  final String? error;

  Map<String, dynamic> toJson() => {
        'schemaVersion': contractSchemaVersion,
        'protocolVersion': contractProtocolVersion,
        'connected': connected,
        if (uri != null) 'uri': uri,
        if (isolateId != null) 'isolateId': isolateId,
        if (bindingVersion != null) 'bindingVersion': bindingVersion,
        if (connectedAt != null)
          'connectedAt': connectedAt!.toUtc().toIso8601String(),
        if (error != null) 'error': error,
      };
}

/// A rectangular screen region occupied by an interactive element.
class ElementBounds {
  const ElementBounds({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  factory ElementBounds.fromJson(Map<String, dynamic> json) {
    final width = _requiredNumber(json, 'width');
    final height = _requiredNumber(json, 'height');
    if (width < 0) _invalid('width', 'must be non-negative');
    if (height < 0) _invalid('height', 'must be non-negative');
    return ElementBounds(
      x: _requiredNumber(json, 'x'),
      y: _requiredNumber(json, 'y'),
      width: width,
      height: height,
    );
  }

  final double x;
  final double y;
  final double width;
  final double height;

  Map<String, dynamic> toJson() => {
        'x': x,
        'y': y,
        'width': width,
        'height': height,
      };
}

/// One interactive widget discovered in the current Flutter tree.
class InteractiveElement {
  InteractiveElement({
    this.type,
    this.key,
    this.text,
    this.identifier,
    this.bounds,
    this.visible,
    Map<String, Object?> additionalProperties = const {},
  }) : additionalProperties = Map.unmodifiable(additionalProperties);

  factory InteractiveElement.fromJson(Map<String, dynamic> json) {
    final rawBounds = json['bounds'];
    final bounds = rawBounds == null
        ? null
        : ElementBounds.fromJson(_asJsonMap(rawBounds, 'bounds'));
    final additional = <String, Object?>{};
    for (final entry in json.entries) {
      if ({
        'type',
        'key',
        'text',
        'identifier',
        'bounds',
        'visible',
      }.contains(entry.key)) {
        continue;
      }
      additional[entry.key] = entry.value;
    }

    return InteractiveElement(
      type: _optionalString(json, 'type'),
      key: _optionalString(json, 'key'),
      text: _optionalString(json, 'text'),
      identifier: _optionalString(json, 'identifier'),
      bounds: bounds,
      visible: _optionalBool(json, 'visible'),
      additionalProperties: additional,
    );
  }

  final String? type;
  final String? key;
  final String? text;
  final String? identifier;
  final ElementBounds? bounds;
  final bool? visible;
  final Map<String, Object?> additionalProperties;

  Map<String, dynamic> toJson() => {
        ...additionalProperties,
        if (type != null) 'type': type,
        if (key != null) 'key': key,
        if (text != null) 'text': text,
        if (identifier != null) 'identifier': identifier,
        if (bounds != null) 'bounds': bounds!.toJson(),
        if (visible != null) 'visible': visible,
      };
}

/// A point-in-time interactive element discovery result.
class InteractiveElementSnapshot {
  InteractiveElementSnapshot({
    required List<InteractiveElement> elements,
    this.capturedAt,
  }) : elements = List.unmodifiable(elements);

  factory InteractiveElementSnapshot.fromJson(Map<String, dynamic> json) {
    _validateVersions(json);
    final rawElements = json['elements'];
    if (rawElements is! List) {
      _invalid('elements', 'must be a list');
    }
    final elements = <InteractiveElement>[];
    for (var i = 0; i < rawElements.length; i++) {
      final raw = rawElements[i];
      if (raw is! Map) {
        _invalid('elements[$i]', 'must be an object');
      }
      elements.add(InteractiveElement.fromJson(
        _asJsonMap(raw, 'elements[$i]'),
      ));
    }
    final count = _optionalInt(json, 'count');
    if (count != null && count != elements.length) {
      _invalid('count', 'does not match elements.length');
    }
    return InteractiveElementSnapshot(
      elements: elements,
      capturedAt: _optionalTime(json, 'capturedAt'),
    );
  }

  final List<InteractiveElement> elements;
  final DateTime? capturedAt;

  int get count => elements.length;

  Map<String, dynamic> toJson() => {
        'schemaVersion': contractSchemaVersion,
        'protocolVersion': contractProtocolVersion,
        'elements': [for (final element in elements) element.toJson()],
        'count': count,
        if (capturedAt != null)
          'capturedAt': capturedAt!.toUtc().toIso8601String(),
      };
}
