import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:fibpop_mobile/engine/action_cards.dart';
import 'package:fibpop_mobile/engine/attacks.dart';
import 'package:fibpop_mobile/engine/cornered.dart';
import 'package:fibpop_mobile/engine/departures.dart';
import 'package:fibpop_mobile/engine/game_state.dart';
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

MatchState corneredState(Map<String, Object?> base) {
  final initial = scenarioState(base, {
    'players': {
      'player-1': {
        'hand': ['card_01:1'],
      },
      'player-2': {'hearts': 1},
    },
  });
  var state = startAttack(initial, 'player-1', 'player-2', 'card_01:1');
  for (final playerId in ['player-2', 'player-3', 'player-4', 'player-1']) {
    state = respondToAttack(
      state,
      playerId,
      const AttackResponse.pass(),
      nowMs: 0,
    );
  }
  return state;
}

MatchState executeDepartureStep(
  MatchState state,
  Map<String, Object?> command,
) {
  switch (command['type']) {
    case 'ATTACK':
      return startAttack(
        state,
        command['actor'] as String,
        command['target'] as String,
        command['card'] as String,
      );
    case 'DEPARTURE':
      final departure = object(command['departure']);
      final parsed = switch (departure['kind']) {
        'disconnect' => const DisconnectDeparture(),
        'forfeit' => ForfeitDeparture(departure['nowMs'] as int),
        _ => throw StateError('Unknown departure kind'),
      };
      return handlePlayerDeparture(state, command['actor'] as String, parsed);
    default:
      throw StateError(
        'Unsupported departure fixture command: ${command['type']}',
      );
  }
}

Matcher engineError(String code) =>
    throwsA(isA<EngineException>().having((error) => error.code, 'code', code));

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
    'disconnect-does-not-change-state',
    'impostor-forfeit-cancels',
    'last-innocent-forfeit-wins',
    'attack-target-forfeit-cancels-attack',
  };
  final scenarios = (suite['scenarios'] as List)
      .map(object)
      .where((scenario) => scenarioNames.contains(scenario['name']))
      .toList();

  test('matches shared departure and terminal outcome scenarios', () {
    expect(
      scenarios.map((scenario) => scenario['name']).toSet(),
      scenarioNames,
    );
    for (final scenario in scenarios) {
      var state = scenarioState(base, object(scenario['initialState']));
      for (final rawStep in scenario['steps'] as List) {
        final step = object(rawStep);
        final command = object(step['command']);
        state = executeDepartureStep(state, command);
        expect(MatchState.fromJson(state.toJson()).toJson(), state.toJson());
      }
      expectSubset(
        state.toJson(),
        scenario['expectedState'],
        scenario['name'] as String,
      );
    }
  });

  test('a forfeited turn owner advances and skips a Cornered player', () {
    final state = scenarioState(base, {
      'players': {
        'player-2': {'status': 'cornered', 'hearts': 0},
      },
    });
    final next = handlePlayerDeparture(
      state,
      'player-1',
      const ForfeitDeparture(0),
    );
    expect(next.phase, TurnPhase.turnStart);
    expect(next.currentPlayerId, 'player-3');
    expect(next.players['player-1']!.status, PlayerStatus.eliminated);
    expect(next.players['player-2']!.status, PlayerStatus.active);
    expect(next.players['player-2']!.hearts, 1);
  });

  test(
    'forfeiting an attacker advances the turn and a Step In responder is skipped',
    () {
      final state = scenarioState(base, {
        'players': {
          'player-1': {
            'hand': ['card_01:1'],
          },
        },
      });
      final attack = startAttack(state, 'player-1', 'player-2', 'card_01:1');
      final attackerForfeits = handlePlayerDeparture(
        attack,
        'player-1',
        const ForfeitDeparture(0),
      );
      expect(attackerForfeits.phase, TurnPhase.turnStart);
      expect(attackerForfeits.currentPlayerId, 'player-2');
      expect(attackerForfeits.pendingAttack, isNull);

      final targetPasses = respondToAttack(
        attack,
        'player-2',
        const AttackResponse.pass(),
        nowMs: 0,
      );
      final responderForfeits = handlePlayerDeparture(
        targetPasses,
        'player-3',
        const ForfeitDeparture(1),
      );
      expect(
        responderForfeits.players['player-3']!.status,
        PlayerStatus.eliminated,
      );
      expect(currentAttackResponder(responderForfeits), 'player-4');
    },
  );

  test(
    'forfeiting a Cornered target resumes play; a forfeited accuser passes',
    () {
      final initial = corneredState(base);
      expect(initial.phase, TurnPhase.awaitingAccusation);
      final targetForfeits = handlePlayerDeparture(
        initial,
        'player-2',
        const ForfeitDeparture(1),
      );
      expect(targetForfeits.phase, TurnPhase.activeTurn);
      expect(targetForfeits.pendingCornered, isNull);
      expect(
        targetForfeits.players['player-2']!.status,
        PlayerStatus.eliminated,
      );

      final accuserForfeits = handlePlayerDeparture(
        initial,
        'player-1',
        const ForfeitDeparture(1),
      );
      expect(
        accuserForfeits.players['player-1']!.status,
        PlayerStatus.eliminated,
      );
      expect(currentAccusationPlayerId(accuserForfeits), 'player-1');
      final nextOffer = expireAccusationOffer(accuserForfeits, 10000);
      expect(currentAccusationPlayerId(nextOffer), 'player-3');
    },
  );

  test(
    'a forfeited Secret Finish participant is removed without unsealing',
    () {
      var state = corneredState(base);
      for (final deadline in [10000, 20000, 30000]) {
        state = expireAccusationOffer(state, deadline);
      }
      state = submitSecretFinishChoice(state, 'player-1', 'pass', 30001);
      final afterForfeit = handlePlayerDeparture(
        state,
        'player-3',
        const ForfeitDeparture(30002),
      );
      expect(afterForfeit.phase, TurnPhase.awaitingSecretFinish);
      expect(afterForfeit.pendingSecretFinish!.eligiblePlayerIds, [
        'player-1',
        'player-4',
      ]);
      expect(afterForfeit.pendingSecretFinish!.submissions, {
        'player-1': 'pass',
      });
    },
  );

  test('a forfeiting Stir the Pot target cancels remaining discards', () {
    final initial = scenarioState(base, {
      'players': {
        'player-1': {
          'hand': ['card_15:1'],
        },
        'player-2': {
          'hand': ['card_09:1'],
        },
        'player-3': {
          'hand': ['card_10:1'],
        },
      },
    });
    final pending = playStirThePot(initial, 'player-1', [
      'player-2',
      'player-3',
    ], 'card_15:1');
    final firstDiscard = respondToCardEffectDiscard(
      pending,
      'player-2',
      'card_09:1',
    );
    final forfeited = handlePlayerDeparture(
      firstDiscard.state,
      'player-3',
      const ForfeitDeparture(0),
    );
    expect(forfeited.phase, TurnPhase.activeTurn);
    expect(forfeited.pendingCardEffect, isNull);
    expect(forfeited.players['player-3']!.status, PlayerStatus.eliminated);
    expect(forfeited.discardPile, ['card_15:1', 'card_09:1']);
  });

  test(
    'rejects invalid players, duplicate forfeits and invalid timestamps',
    () {
      final state = MatchState.fromJson(base);
      expect(
        () => handlePlayerDeparture(
          state,
          'missing',
          const DisconnectDeparture(),
        ),
        engineError('INVALID_PLAYER'),
      );
      final forfeited = handlePlayerDeparture(
        state,
        'player-2',
        const ForfeitDeparture(0),
      );
      expect(
        () => handlePlayerDeparture(
          forfeited,
          'player-2',
          const ForfeitDeparture(1),
        ),
        engineError('NOT_ELIGIBLE'),
      );
      expect(
        () => handlePlayerDeparture(
          state,
          'player-2',
          const ForfeitDeparture(-1),
        ),
        engineError('INVALID_DEADLINE'),
      );
    },
  );
}
