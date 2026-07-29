import 'package:marionette_mcp/src/contracts.dart';
import 'package:test/test.dart';

void main() {
  test('contract envelopes carry schema and protocol versions', () {
    final json = InteractiveElementSnapshot(elements: const []).toJson();
    expect(json['schemaVersion'], contractSchemaVersion);
    expect(json['protocolVersion'], contractProtocolVersion);
    expect(ConnectionInfo.disconnected().toJson()['schemaVersion'],
        contractSchemaVersion);
  });

  test('interactive snapshots preserve typed element JSON', () {
    final snapshot = InteractiveElementSnapshot(
      capturedAt: DateTime.utc(2026, 7, 29, 12),
      elements: [
        InteractiveElement(
          type: 'ElevatedButton',
          key: 'submit',
          text: 'Submit',
          visible: true,
          bounds: const ElementBounds(x: 1, y: 2, width: 3, height: 4),
          additionalProperties: const {'enabled': 'true'},
        ),
      ],
    );

    final json = snapshot.toJson();
    expect(json['count'], 1);
    expect((json['elements'] as List).single, {
      'enabled': 'true',
      'type': 'ElevatedButton',
      'key': 'submit',
      'text': 'Submit',
      'bounds': {'x': 1.0, 'y': 2.0, 'width': 3.0, 'height': 4.0},
      'visible': true,
    });
  });

  test('log snapshots expose entries and cursor while retaining legacy logs',
      () {
    final snapshot = LogSnapshot.fromJson({
      'entries': [
        {
          'sequence': 7,
          'timestamp': '2026-07-29T12:00:00Z',
          'severity': 'warning',
          'source': 'test',
          'message': 'slow response',
          'error': 'TimeoutException',
          'stack': 'stack line',
        },
      ],
      'logs': ['slow response'],
      'count': 1,
      'cursor': 7,
      'afterSequence': 6,
    });

    expect(snapshot.entries.single.sequence, 7);
    expect(snapshot.entries.single.severity, LogSeverity.warning);
    expect(snapshot.entries.single.error, 'TimeoutException');
    expect(snapshot.toJson()['cursor'], 7);
    expect(snapshot.toJson()['logs'], ['slow response']);
    expect(
      (snapshot.toJson()['entries'] as List).single['severity'],
      'warning',
    );
  });

  test('gesture outcomes are diagnostic and machine-readable', () {
    final outcome = DiagnosticGestureOutcome.fromResponse('tap', {
      'message': 'Tapped submit',
    });

    expect(outcome.toJson(), containsPair('gesture', 'tap'));
    expect(outcome.toJson(), containsPair('success', true));
    expect(outcome.toJson(), containsPair('status', 'success'));
    expect(outcome.toJson(), containsPair('message', 'Tapped submit'));
  });

  test('corrupt bounds and elements are rejected as typed failures', () {
    expect(
      () => ElementBounds.fromJson({'x': 1, 'y': 2, 'width': 3}),
      throwsA(isA<ContractFormatException>()),
    );
    expect(
      () => InteractiveElementSnapshot.fromJson({
        'elements': [null],
      }),
      throwsA(isA<ContractFormatException>()),
    );
  });

  test('structured logs require timestamp and preserve legacy text without one',
      () {
    expect(
      () => StructuredLogEntry.fromJson({
        'sequence': 1,
        'severity': 'error',
        'source': 'test',
        'message': 'missing timestamp',
      }),
      throwsA(isA<ContractFormatException>()),
    );

    final legacy = LogSnapshot.fromJson({
      'logs': ['legacy']
    });
    expect(legacy.entries, isEmpty);
    expect(legacy.legacyLogs, ['legacy']);
    expect(legacy.toJson()['count'], 1);
  });

  test('corrupt log entries and versions are rejected', () {
    expect(
      () => LogSnapshot.fromJson({
        'schemaVersion': contractSchemaVersion + 1,
        'entries': [],
        'cursor': 0,
      }),
      throwsA(isA<ContractFormatException>()),
    );
    expect(
      () => LogSnapshot.fromJson({
        'entries': [
          {
            'sequence': 1,
            'timestamp': 'not-a-timestamp',
            'severity': 'error',
            'source': 'test',
            'message': 'bad timestamp',
          },
        ],
        'cursor': 1,
      }),
      throwsA(isA<ContractFormatException>()),
    );
    expect(
      () => StructuredLogEntry.fromJson({
        'sequence': 1,
        'timestamp': '2026-07-29T12:00:00Z',
        'severity': 'unknown',
        'source': 'test',
        'message': 'bad severity',
      }),
      throwsA(isA<ContractFormatException>()),
    );
  });

  test('severity codec is finite and legacy conversion is explicit', () {
    expect(LogSeverity.values.map((value) => value.value), [
      'debug',
      'info',
      'warning',
      'error',
      'critical',
      'fatal',
    ]);
    expect(LogSeverity.fromLegacy('WARN'), LogSeverity.warning);
    expect(
      StructuredLogEntry.fromLegacy(
        sequence: 1,
        timestamp: DateTime.utc(2026, 7, 29, 12),
        severity: 'ERROR',
        source: 'legacy',
        message: 'legacy error',
      ).severity,
      LogSeverity.error,
    );
    expect(
      () => LogSeverity.fromLegacy('notice'),
      throwsA(isA<ContractFormatException>()),
    );
  });
}
