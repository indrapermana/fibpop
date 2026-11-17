import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:fibpop_mobile/engine/attacks.dart';
import 'package:fibpop_mobile/engine/cornered.dart';
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

MatchState executeCorneredStep(MatchState state, Map<String, Object?> command) {
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
      final parsed = switch (response['kind']) {
        'pass' => AttackResponse.pass(
          discardCardInstanceId: response['discardCardInstanceId'] as String?,
        ),
        'defend' => AttackResponse.defend(response['cardInstanceId'] as String),
        'step_in' => AttackResponse.stepIn(
          response['cardInstanceId'] as String,
        ),
        _ => throw StateError('Unknown attack response'),
      };
      return respondToAttack(
        state,
        command['actor'] as String,
        parsed,
        nowMs: command['nowMs'] as int?,
      );
    case 'ACCUSE':
      final response = command['response'];
      final parsed = switch (response) {
        'pass' => const AccusationResponse.pass(),
        'accuse' => const AccusationResponse.accuse(),
        _ => throw StateError('Unknown accusation response: $response'),
      };
      return respondToAccusation(
        state,
        command['actor'] as String,
        parsed,
        command['nowMs'] as int,
      );
    case 'EXPIRE_ACCUSATION':
      return expireAccusationOffer(state, command['nowMs'] as int);
    case 'SECRET_CHOICE':
      return submitSecretFinishChoice(
        state,
        command['actor'] as String,
        command['choice'] as String,
        command['nowMs'] as int,
      );
    case 'EXPIRE_SECRET':
      return expireSecretFinishWindow(state, command['nowMs'] as int);
    case 'PLAY_LAST_CHANCE':
      return playLastChance(
        state,
        command['actor'] as String,
        command['card'] as String,
        command['nowMs'] as int,
      );
    case 'PASS_LAST_CHANCE':
      return passLastChance(
        state,
        command['actor'] as String,
        command['nowMs'] as int,
      );
    case 'EXPIRE_LAST_CHANCE':
      return expireLastChanceWindow(state, command['nowMs'] as int);
    default:
      throw StateError(
        'Unsupported Cornered fixture command: ${command['type']}',
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
    'last-chance-sealed-window',
    'correct-accusation-wins',
    'wrong-accusation-eliminates-both',
    'secret-finish-remains-sealed-until-expiry',
    'wrong-accusation-final-innocents',
    'secret-finish-final-innocent',
  };
  final scenarios = (suite['scenarios'] as List)
      .map(object)
      .where((scenario) => scenarioNames.contains(scenario['name']))
      .toList();

  test(
    'matches shared Cornered, accusation, Secret Finish and Last Chance scenarios',
    () {
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
              () => executeCorneredStep(state, command),
              engineError(step['expectedError'] as String),
              reason: scenario['name'] as String,
            );
            expect(state.toJson(), before);
            continue;
          }
          state = executeCorneredStep(state, command);
          expect(state.toJson(), isNot(before));
          expect(MatchState.fromJson(state.toJson()).toJson(), state.toJson());
        }
        expectSubset(
          state.toJson(),
          scenario['expectedState'],
          scenario['name'] as String,
        );
      }
    },
  );

  test('pads accusation turns and requires each deadline before advancing', () {
    final baseState = scenarioState(base, {
      'players': {
        'player-1': {
          'hand': ['card_01:1'],
          'evidence': {
            'player-2': {'clue': true, 'behavior': true},
          },
        },
        'player-2': {'hearts': 1},
      },
    });
    var state = startAttack(baseState, 'player-1', 'player-2', 'card_01:1');
    for (final id in ['player-2', 'player-3', 'player-4', 'player-1']) {
      state = respondToAttack(state, id, const AttackResponse.pass(), nowMs: 0);
    }
    expect(currentAccusationPlayerId(state), 'player-1');
    expect(
      () => respondToAccusation(
        state,
        'player-1',
        const AccusationResponse.pass(),
        -1,
      ),
      engineError('INVALID_DEADLINE'),
    );
    final passed = respondToAccusation(
      state,
      'player-1',
      const AccusationResponse.pass(),
      1,
    );
    expect(currentAccusationPlayerId(passed), 'player-1');
    expect(
      () => respondToAccusation(
        passed,
        'player-1',
        const AccusationResponse.accuse(),
        2,
      ),
      engineError('INVALID_ACCUSATION'),
    );
    expect(
      () => expireAccusationOffer(passed, 9999),
      engineError('WINDOW_NOT_EXPIRED'),
    );
    final next = expireAccusationOffer(passed, 10000);
    expect(currentAccusationPlayerId(next), 'player-3');
    expect(next.deadlineUtc, '1970-01-01T00:00:20.000Z');
  });

  test(
    'rejects unauthorized and repeated Secret Finish choices without mutating state',
    () {
      final state = scenarioState(base, {
        'players': {
          'player-1': {
            'hand': ['card_01:1'],
          },
          'player-2': {'hearts': 1},
        },
      });
      var cornered = startAttack(state, 'player-1', 'player-2', 'card_01:1');
      for (final id in ['player-2', 'player-3', 'player-4', 'player-1']) {
        cornered = respondToAttack(
          cornered,
          id,
          const AttackResponse.pass(),
          nowMs: 0,
        );
      }
      for (final time in [10000, 20000, 30000]) {
        cornered = expireAccusationOffer(cornered, time);
      }
      expect(cornered.phase, TurnPhase.awaitingSecretFinish);
      final before = cornered.toJson();
      expect(
        () => submitSecretFinishChoice(cornered, 'player-1', 'finish', 30001),
        engineError('NOT_ELIGIBLE'),
      );
      expect(cornered.toJson(), before);
      final pass = submitSecretFinishChoice(
        cornered,
        'player-1',
        'pass',
        30001,
      );
      expect(
        () => submitSecretFinishChoice(pass, 'player-1', 'pass', 30002),
        engineError('NOT_ELIGIBLE'),
      );
      expect(pass.pendingSecretFinish!.submissions, {'player-1': 'pass'});
      expect(pass.pendingSecretFinish!.eligiblePlayerIds, [
        'player-1',
        'player-3',
        'player-4',
      ]);
    },
  );

  test(
    'a Cornered Impostor receives a pass-only Secret Finish cover window',
    () {
      final state = scenarioState(base, {
        'players': {
          'player-1': {
            'hand': ['card_01:1'],
          },
          'player-2': {'hearts': 1, 'role': 'impostor'},
          'player-4': {'role': 'innocent'},
        },
      });
      var cornered = startAttack(state, 'player-1', 'player-2', 'card_01:1');
      for (final id in ['player-2', 'player-3', 'player-4', 'player-1']) {
        cornered = respondToAttack(
          cornered,
          id,
          const AttackResponse.pass(),
          nowMs: 0,
        );
      }
      for (final time in [10000, 20000, 30000]) {
        cornered = expireAccusationOffer(cornered, time);
      }
      expect(cornered.phase, TurnPhase.awaitingSecretFinish);
      expect(
        () => submitSecretFinishChoice(cornered, 'player-4', 'finish', 30001),
        engineError('NOT_ELIGIBLE'),
      );
      final result = expireSecretFinishWindow(cornered, 40000);
      expect(result.phase, TurnPhase.awaitingLastChance);
      expect(currentLastChancePlayerId(result), 'player-2');
    },
  );

  test(
    'Last Chance submission stays pending until expiry, then restores one Heart',
    () {
      final state = scenarioState(base, {
        'players': {
          'player-1': {
            'hand': ['card_01:1'],
          },
          'player-2': {
            'hearts': 1,
            'hand': ['card_19:1'],
          },
        },
      });
      var cornered = startAttack(state, 'player-1', 'player-2', 'card_01:1');
      for (final id in ['player-2', 'player-3', 'player-4', 'player-1']) {
        cornered = respondToAttack(
          cornered,
          id,
          const AttackResponse.pass(),
          nowMs: 0,
        );
      }
      for (final time in [10000, 20000, 30000]) {
        cornered = expireAccusationOffer(cornered, time);
      }
      final noFinish = expireSecretFinishWindow(cornered, 40000);
      expect(noFinish.phase, TurnPhase.awaitingLastChance);
      final submitted = playLastChance(
        noFinish,
        'player-2',
        'card_19:1',
        40001,
      );
      expect(submitted.players['player-2']!.status, PlayerStatus.cornered);
      final recovered = expireLastChanceWindow(submitted, 50000);
      expect(recovered.phase, TurnPhase.activeTurn);
      expect(recovered.players['player-2']!.status, PlayerStatus.active);
      expect(recovered.players['player-2']!.hearts, 1);
      expect(recovered.players['player-2']!.hand, isEmpty);
      expect(recovered.discardPile, ['card_01:1', 'card_19:1']);
      expect(recovered.pendingCornered, isNull);
    },
  );
}
