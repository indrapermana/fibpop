import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:fibpop_mobile/engine/events.dart';
import 'package:fibpop_mobile/engine/game_state.dart';
import 'package:fibpop_mobile/engine/suspicion.dart';
import 'package:fibpop_mobile/engine/turns.dart';

Map<String, Object?> object(Object? value) =>
    (value as Map).cast<String, Object?>();

void main() {
  final suite = object(
    jsonDecode(
      File(
        '../../shared/fixtures/m1-gameplay-scenarios.json',
      ).readAsStringSync(),
    ),
  );
  final initial = MatchState.fromJson(object(suite['baseState']));

  test('records, serializes and replays authoritative state transitions', () {
    final first = adjustSuspicion(initial, 'player-1', 1);
    final second = adjustSuspicion(first, 'player-2', 2);
    final events = [
      recordTransition(initial, first),
      recordTransition(first, second),
    ];
    final serializedEvents = jsonDecode(jsonEncode(events)) as List<Object?>;

    expect(
      applyTransition(initial, serializedEvents.first).toJson(),
      first.toJson(),
    );
    expect(
      replayTransitions(initial, serializedEvents).toJson(),
      second.toJson(),
    );
    expect(initial.players['player-1']!.suspicion, 0);
  });

  test('rejects invalid, stale, reordered and cross-match transitions', () {
    final next = adjustSuspicion(initial, 'player-1', 1);
    final event = recordTransition(initial, next);
    expect(() => applyTransition(next, event), engineError('INVALID_EVENT'));
    expect(
      () => applyTransition(initial, {...event, 'matchId': 'other-match'}),
      engineError('INVALID_EVENT'),
    );
    expect(
      () => applyTransition(initial, {...event, 'version': 3}),
      engineError('INVALID_EVENT'),
    );
    expect(
      () => applyTransition(initial, {
        ...event,
        'changes': {'secret': true},
      }),
      engineError('INVALID_EVENT'),
    );
    expect(
      () => recordTransition(initial, initial),
      engineError('INVALID_EVENT'),
    );
    expect(
      () => replayTransitions(initial, [event, event]),
      engineError('INVALID_EVENT'),
    );
  });

  test('transition changes do not retain authoritative state collections', () {
    final next = adjustSuspicion(initial, 'player-1', 1);
    final event = recordTransition(initial, next);
    final changes = object(event['changes']);
    final players = object(changes['players']);
    final player = object(players['player-1']);
    (player['hand'] as List<Object?>).add('mutation');

    expect(next.players['player-1']!.hand, isEmpty);
    expect(initial.players['player-1']!.hand, isEmpty);
  });
}

Matcher engineError(String code) =>
    throwsA(isA<EngineException>().having((error) => error.code, 'code', code));
