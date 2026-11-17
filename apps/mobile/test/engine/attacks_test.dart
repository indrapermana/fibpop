import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:fibpop_mobile/engine/attacks.dart';
import 'package:fibpop_mobile/engine/game_state.dart';
import 'package:fibpop_mobile/engine/random.dart';
import 'package:fibpop_mobile/engine/turns.dart';

Map<String, Object?> object(Object? value) =>
    (value as Map).cast<String, Object?>();

void expectSubset(Object? actual, Object? expected, [String path = 'root']) {
  if (expected is Map) {
    expect(actual, isA<Map>(), reason: path);
    final actualMap = actual as Map;
    for (final entry in expected.entries) {
      expect(
        actualMap.containsKey(entry.key),
        isTrue,
        reason: '$path.${entry.key}',
      );
      expectSubset(actualMap[entry.key], entry.value, '$path.${entry.key}');
    }
  } else if (expected is List) {
    expect(actual, isA<List>(), reason: path);
    final actualList = actual as List;
    expect(actualList, hasLength(expected.length), reason: path);
    for (var index = 0; index < expected.length; index++) {
      expectSubset(actualList[index], expected[index], '$path[$index]');
    }
  } else {
    expect(actual, expected, reason: path);
  }
}

MatchState scenarioState(
  Map<String, Object?> base,
  Map<String, Object?> overrides,
) {
  final players = Map<String, Object?>.from(object(base['players']));
  for (final entry in object(overrides['players'] ?? {}).entries) {
    if (!players.containsKey(entry.key)) {
      throw StateError('Unknown fixture player ${entry.key}');
    }
    players[entry.key] = {
      ...object(players[entry.key]),
      ...object(entry.value),
    };
  }
  return MatchState.fromJson({...base, ...overrides, 'players': players});
}

MatchState executeAttackStep(MatchState state, Map<String, Object?> command) {
  switch (command['type']) {
    case 'ATTACK':
      return startAttack(
        state,
        command['actor'] as String,
        command['target'] as String,
        command['card'] as String,
      );
    case 'ATTACK_RESPONSE':
      final response = object(command['response']);
      final kind = response['kind'];
      final parsed = switch (kind) {
        'pass' => AttackResponse.pass(
          discardCardInstanceId: response['discardCardInstanceId'] as String?,
        ),
        'defend' => AttackResponse.defend(response['cardInstanceId'] as String),
        'step_in' => AttackResponse.stepIn(
          response['cardInstanceId'] as String,
        ),
        _ => throw StateError('Unsupported attack response: $kind'),
      };
      return respondToAttack(
        state,
        command['actor'] as String,
        parsed,
        nowMs: command['nowMs'] as int?,
      );
    default:
      throw StateError(
        'Unsupported attack fixture command: ${command['type']}',
      );
  }
}

Matcher engineError(String code) =>
    throwsA(isA<EngineException>().having((error) => error.code, 'code', code));

class FixtureRandom implements RandomSource {
  FixtureRandom(this.value);
  final double value;

  @override
  double next() => value;
}

void main() {
  final suite = object(
    jsonDecode(
      File(
        '../../shared/fixtures/m1-gameplay-scenarios.json',
      ).readAsStringSync(),
    ),
  );
  final base = object(suite['baseState']);
  const scenarioNames = {
    'attack-damage',
    'double-down-discard',
    'callout-reveals-action',
    'corner-them-evidence-even-if-blocked',
    'deny-it',
    'step-in-after-target',
    'countercheck-behavior-evidence',
    'shield-consumed-by-damage',
  };
  final scenarios = (suite['scenarios'] as List)
      .map(object)
      .where((scenario) => scenarioNames.contains(scenario['name']))
      .toList();

  test('runs the selected shared attack scenarios', () {
    expect(
      scenarios.map((scenario) => scenario['name']).toSet(),
      scenarioNames,
    );
    for (final scenario in scenarios) {
      var state = scenarioState(base, object(scenario['initialState']));
      for (final rawStep in scenario['steps'] as List) {
        final step = object(rawStep);
        final command = object(step['command']);
        final before = state.toJson();
        if (step['expectedError'] != null) {
          expect(
            () => executeAttackStep(state, command),
            engineError(step['expectedError'] as String),
            reason: scenario['name'] as String,
          );
          expect(state.toJson(), before);
          continue;
        }
        state = executeAttackStep(state, command);
      }
      expectSubset(
        state.toJson(),
        scenario['expectedState'],
        scenario['name'] as String,
      );
      if (scenario['name'] == 'callout-reveals-action') {
        expect(
          state.pendingAttack?.calloutRevealedActionCardInstanceId,
          'card_14:1',
        );
      }
    }
  });

  test(
    'attack validates ownership, target, limits and phase without mutation',
    () {
      final initial = scenarioState(base, {
        'players': {
          'player-1': {
            'hand': ['card_01:1'],
          },
        },
      });
      final before = initial.toJson();
      expect(
        () => startAttack(initial, 'player-1', 'player-2', 'card_01:2'),
        engineError('INVALID_CARD'),
      );
      expect(
        () => startAttack(initial, 'player-1', 'player-1', 'card_01:1'),
        engineError('INVALID_TARGET'),
      );
      expect(
        () => startAttack(initial, 'player-2', 'player-1', 'card_01:1'),
        engineError('NOT_YOUR_TURN'),
      );
      final attack = startAttack(initial, 'player-1', 'player-2', 'card_01:1');
      expect(
        () => startAttack(
          initial.copyWith(attacksUsedThisTurn: 1),
          'player-1',
          'player-2',
          'card_01:1',
        ),
        engineError('ATTACK_LIMIT'),
      );
      expect(attack.phase, TurnPhase.awaitingReaction);
      expect(initial.toJson(), before);
    },
  );

  test('damage that corners a player opens the first accusation slot', () {
    final state = scenarioState(base, {
      'players': {
        'player-1': {
          'hand': ['card_01:1'],
        },
        'player-2': {'hearts': 1},
      },
    });
    var pending = startAttack(state, 'player-1', 'player-2', 'card_01:1');
    for (final playerId in ['player-2', 'player-3', 'player-4', 'player-1']) {
      pending = respondToAttack(
        pending,
        playerId,
        const AttackResponse.pass(),
        nowMs: 1000,
      );
    }
    expect(pending.phase, TurnPhase.awaitingAccusation);
    expect(pending.players['player-2']!.status, PlayerStatus.cornered);
    expect(pending.players['player-2']!.hearts, 0);
    expect(pending.pendingCornered!.accusationOrderPlayerIds, [
      'player-1',
      'player-3',
      'player-4',
    ]);
    expect(pending.deadlineUtc, '1970-01-01T00:00:11.000Z');
    expect(pending.suspicionAwardedForDamageThisTurn, isTrue);
    expect(MatchState.fromJson(pending.toJson()).toJson(), pending.toJson());
  });

  test(
    'Double Down discard is applied only on damage; Safe Place blocks damage',
    () {
      final state = scenarioState(base, {
        'players': {
          'player-1': {
            'hand': ['card_02:1'],
          },
          'player-2': {
            'hand': ['card_09:1'],
          },
        },
      });
      final attack = startAttack(state, 'player-1', 'player-2', 'card_02:1');
      expect(
        () => respondToAttack(attack, 'player-2', const AttackResponse.pass()),
        engineError('INVALID_DISCARD'),
      );
      final withShield = attack.copyWith(
        activeEffects: const [
          SafePlaceEffect(
            casterPlayerId: 'player-4',
            targetPlayerId: 'player-2',
          ),
        ],
      );
      var result = respondToAttack(
        withShield,
        'player-2',
        const AttackResponse.pass(discardCardInstanceId: 'card_09:1'),
      );
      for (final playerId in ['player-3', 'player-4', 'player-1']) {
        result = respondToAttack(
          result,
          playerId,
          const AttackResponse.pass(),
          nowMs: 0,
        );
      }
      expect(result.players['player-2']!.hearts, 3);
      expect(result.players['player-2']!.hand, ['card_09:1']);
      expect(result.activeEffects, isEmpty);
      expect(result.publicActionHistory, isEmpty);
    },
  );

  test(
    'Safe Place is cast once on an Active target and consumed only by damage',
    () {
      final state = scenarioState(base, {
        'players': {
          'player-1': {
            'hand': ['card_21:1', 'card_21:2'],
          },
        },
      });
      final shielded = playSafePlace(
        state,
        'player-1',
        'player-2',
        'card_21:1',
      );
      expect(shielded.actionsRemaining, 1);
      expect(
        () => playSafePlace(shielded, 'player-1', 'player-2', 'card_21:2'),
        engineError('SAFE_PLACE_ALREADY_ACTIVE'),
      );
      final attackState = scenarioState(base, {
        'players': {
          'player-1': {
            'hand': ['card_01:1'],
          },
        },
        'activeEffects': shielded.activeEffects
            .map((effect) => effect.toJson())
            .toList(),
      });
      var result = startAttack(
        attackState,
        'player-1',
        'player-2',
        'card_01:1',
      );
      for (final playerId in ['player-2', 'player-3', 'player-4', 'player-1']) {
        result = respondToAttack(
          result,
          playerId,
          const AttackResponse.pass(),
          nowMs: 0,
        );
      }
      expect(result.players['player-2']!.hearts, 3);
      expect(result.players['player-1']!.suspicion, 0);
      expect(result.publicActionHistory, isEmpty);
    },
  );

  test(
    'requires an injected deadline only if damage would Corner the target',
    () {
      final state = scenarioState(base, {
        'players': {
          'player-1': {
            'hand': ['card_01:1'],
          },
          'player-2': {'hearts': 1},
        },
      });
      var pending = startAttack(state, 'player-1', 'player-2', 'card_01:1');
      for (final playerId in ['player-2', 'player-3', 'player-4']) {
        pending = respondToAttack(
          pending,
          playerId,
          const AttackResponse.pass(),
        );
      }
      expect(
        () => respondToAttack(pending, 'player-1', const AttackResponse.pass()),
        engineError('INVALID_DEADLINE'),
      );
      expect(pending.phase, TurnPhase.awaitingReaction);
      expect(pending.players['player-2']!.hearts, 1);
    },
  );
}
