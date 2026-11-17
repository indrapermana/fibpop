import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:fibpop_mobile/engine/game_state.dart';
import 'package:fibpop_mobile/engine/investigations.dart';
import 'package:fibpop_mobile/engine/random.dart';
import 'package:fibpop_mobile/engine/turns.dart';

class SequenceRandom implements RandomSource {
  SequenceRandom(this.values);

  final List<double> values;
  var index = 0;

  @override
  double next() {
    if (index >= values.length) {
      throw StateError('Fixture random sequence exhausted');
    }
    return values[index++];
  }
}

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
    expect(actualList.length, expected.length, reason: path);
    for (var i = 0; i < expected.length; i++) {
      expectSubset(actualList[i], expected[i], '$path[$i]');
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
  const names = {
    'look-back-behavior',
    'follow-trail-private-inspection',
    'peek-empty-hand',
    'check-alibi',
    'extra-clue-target-discard',
    'misdirection-blocks-inspection-not-evidence',
    'first-investigation-at-three-suspicion-is-free',
    'basic-observe-qualifying-history',
  };
  final scenarios = (suite['scenarios'] as List)
      .map(object)
      .where((scenario) => names.contains(scenario['name']))
      .toList();

  test('finds all selected shared investigation scenarios', () {
    expect(scenarios.map((scenario) => scenario['name']).toSet(), names);
  });

  for (final scenario in scenarios) {
    test('shared investigation scenario: ${scenario['name']}', () {
      var state = scenarioState(base, object(scenario['initialState']));
      for (final rawStep in scenario['steps'] as List) {
        final step = object(rawStep);
        if (step.containsKey('expectedError')) {
          throw StateError('Expected-error scenarios are not supported yet');
        }
        final command = object(step['command']);
        final before = state.toJson();
        Map<String, Object?> result;
        switch (command['type']) {
          case 'BASIC_OBSERVE':
            final outcome = basicObserve(
              state,
              command['actor'] as String,
              command['target'] as String,
            );
            expect(state.toJson(), before);
            state = outcome.state;
            result = {'evidenceAdded': outcome.evidenceAdded};
          case 'INVESTIGATE':
            final rawDefense = command['defense'];
            InvestigationDefense? defense;
            if (rawDefense != null) {
              final value = object(rawDefense);
              defense = InvestigationDefense(
                kind: InvestigationDefenseKind.values.byName(
                  value['kind'] as String,
                ),
                cardInstanceId: value['cardInstanceId'] as String,
              );
            }
            final outcome = playInvestigation(
              state,
              actorPlayerId: command['actor'] as String,
              targetPlayerId: command['target'] as String,
              cardInstanceId: command['card'] as String,
              random: SequenceRandom(
                (command['randomSequence'] as List)
                    .map((value) => (value as num).toDouble())
                    .toList(),
              ),
              defense: defense,
            );
            expect(state.toJson(), before);
            state = outcome.state;
            result = outcome.resultToJson();
          default:
            throw StateError(
              'Unsupported investigation fixture command: ${command['type']}',
            );
        }
        if (step['expectedResult'] != null) {
          expectSubset(result, step['expectedResult']);
        }
      }
      expectSubset(state.toJson(), scenario['expectedState']);
    });
  }

  test(
    'evidence is independent by investigator and suspect and duplicates are no-ops',
    () {
      final state = scenarioState(base, {});
      final clue = grantEvidence(
        state,
        'player-1',
        'player-2',
        EvidenceKind.clue,
      );
      expect(
        identical(
          grantEvidence(clue, 'player-1', 'player-2', EvidenceKind.clue),
          clue,
        ),
        isTrue,
      );
      final both = grantEvidence(
        clue,
        'player-1',
        'player-2',
        EvidenceKind.behavior,
      );
      final other = grantEvidence(
        both,
        'player-3',
        'player-2',
        EvidenceKind.clue,
      );
      expect(other.players['player-1']!.evidence['player-2']!.toJson(), {
        'clue': true,
        'behavior': true,
      });
      expect(other.players['player-3']!.evidence['player-2']!.toJson(), {
        'clue': true,
        'behavior': false,
      });
      expect(state.players['player-1']!.evidence, isEmpty);
      expect(
        () => grantEvidence(state, 'missing', 'player-2', EvidenceKind.clue),
        engineError('INVALID_PLAYER'),
      );
      expect(
        () => grantEvidence(state, 'player-1', 'missing', EvidenceKind.clue),
        engineError('INVALID_TARGET'),
      );
    },
  );

  test(
    'observe spends action without history and duplicate behavior does not add evidence',
    () {
      final empty = scenarioState(base, {});
      final noHistory = basicObserve(empty, 'player-1', 'player-2');
      expect(noHistory.evidenceAdded, isFalse);
      expect(noHistory.state.actionsRemaining, 1);
      final state = scenarioState(base, {
        'publicActionHistory': [
          {'playerId': 'player-2', 'kind': 'noisy_manipulation'},
        ],
      });
      final first = basicObserve(state, 'player-1', 'player-2');
      final second = basicObserve(first.state, 'player-1', 'player-2');
      expect(first.evidenceAdded, isTrue);
      expect(second.evidenceAdded, isFalse);
      expect(second.state.version, state.version + 2);
      expect(second.state.actionsRemaining, 0);
      expect(
        () => basicObserve(second.state, 'player-1', 'player-2'),
        engineError('NO_ACTIONS_REMAIN'),
      );
    },
  );

  test('rejects invalid plays and defenses without changing the state', () {
    final state = scenarioState(base, {
      'players': {
        'player-1': {
          'hand': ['card_11:1', 'card_10:1'],
        },
        'player-2': {
          'hand': ['card_09:1'],
        },
      },
    });
    final before = state.toJson();
    InvestigationOutcome play(
      String actor,
      String target,
      String card, [
      InvestigationDefense? defense,
    ]) => playInvestigation(
      state,
      actorPlayerId: actor,
      targetPlayerId: target,
      cardInstanceId: card,
      random: SequenceRandom([]),
      defense: defense,
    );
    expect(
      () => play('player-2', 'player-1', 'card_10:1'),
      engineError('NOT_YOUR_TURN'),
    );
    expect(
      () => play('player-1', 'missing', 'card_10:1'),
      engineError('INVALID_TARGET'),
    );
    expect(
      () => play('player-1', 'player-2', 'card_10:0'),
      engineError('INVALID_CARD'),
    );
    expect(
      () => play('player-1', 'player-2', 'card_09:1'),
      engineError('INVALID_CARD'),
    );
    expect(
      () => play('player-1', 'player-1', 'card_11:1'),
      engineError('INVALID_TARGET'),
    );
    expect(
      () => play(
        'player-1',
        'player-2',
        'card_10:1',
        const InvestigationDefense(
          kind: InvestigationDefenseKind.discard,
          cardInstanceId: 'card_09:1',
        ),
      ),
      engineError('INVALID_INSPECTION_DEFENSE'),
    );
    expect(
      () => play(
        'player-1',
        'player-2',
        'card_10:1',
        const InvestigationDefense(
          kind: InvestigationDefenseKind.misdirection,
          cardInstanceId: 'card_09:1',
        ),
      ),
      engineError('INVALID_INSPECTION_DEFENSE'),
    );
    expect(state.toJson(), before);
  });

  test(
    'Peek recycles its discarded card and inspection consumes finite randomness',
    () {
      final state = scenarioState(base, {
        'players': {
          'player-1': {
            'hand': ['card_11:1'],
          },
          'player-2': {
            'hand': ['target'],
          },
        },
      });
      expect(
        () => playInvestigation(
          state,
          actorPlayerId: 'player-1',
          targetPlayerId: 'player-2',
          cardInstanceId: 'card_11:1',
          random: SequenceRandom([]),
        ),
        throwsStateError,
      );
      final outcome = playInvestigation(
        state,
        actorPlayerId: 'player-1',
        targetPlayerId: 'player-2',
        cardInstanceId: 'card_11:1',
        random: SequenceRandom([0]),
      );
      expect(outcome.inspectedCardInstanceId, 'target');
      expect(outcome.drawnCardInstanceId, 'card_11:1');
      expect(outcome.state.players['player-1']!.hand, ['card_11:1']);
      expect(outcome.state.discardPile, isEmpty);
      expect(outcome.state.toJson().containsKey('privateResult'), isFalse);
    },
  );

  test(
    'first investigation opportunity is used below three; Extra Clue is never discounted',
    () {
      var state = scenarioState(base, {
        'players': {
          'player-1': {
            'hand': ['card_09:1', 'card_09:2', 'card_22:1'],
          },
          'player-2': {'suspicion': 2},
        },
      });
      final first = playInvestigation(
        state,
        actorPlayerId: 'player-1',
        targetPlayerId: 'player-2',
        cardInstanceId: 'card_09:1',
        random: SequenceRandom([]),
      );
      final targetJson = {
        ...first.state.players['player-2']!.toJson(),
        'suspicion': 3,
      };
      state = first.state.copyWith(
        players: {
          ...first.state.players,
          'player-2': PlayerState.fromJson(targetJson),
        },
      );
      final second = playInvestigation(
        state,
        actorPlayerId: 'player-1',
        targetPlayerId: 'player-2',
        cardInstanceId: 'card_09:2',
        random: SequenceRandom([]),
      );
      expect(first.actionCost, 1);
      expect(second.actionCost, 1);
      final extraState = scenarioState(base, {
        'players': {
          'player-1': {
            'hand': ['card_22:1'],
          },
          'player-2': {'suspicion': 3},
        },
      });
      final extra = playInvestigation(
        extraState,
        actorPlayerId: 'player-1',
        targetPlayerId: 'player-2',
        cardInstanceId: 'card_22:1',
        random: SequenceRandom([]),
      );
      expect(extra.actionCost, 1);
      expect(extra.state.investigationTargetsThisTurn, isEmpty);
    },
  );

  test(
    'self-inspection excludes the played card and prevents self Misdirection',
    () {
      final state = scenarioState(base, {
        'players': {
          'player-1': {
            'hand': ['card_10:1', 'card_24:1'],
          },
        },
      });
      final result = playInvestigation(
        state,
        actorPlayerId: 'player-1',
        targetPlayerId: 'player-1',
        cardInstanceId: 'card_10:1',
        random: SequenceRandom([0]),
      );
      expect(result.inspectedCardInstanceId, 'card_24:1');
      expect(result.state.players['player-1']!.hand, ['card_24:1']);
      expect(
        result.state.players['player-1']!.evidence['player-1']!.clue,
        isTrue,
      );
      expect(
        () => playInvestigation(
          state,
          actorPlayerId: 'player-1',
          targetPlayerId: 'player-1',
          cardInstanceId: 'card_10:1',
          random: SequenceRandom([]),
          defense: const InvestigationDefense(
            kind: InvestigationDefenseKind.misdirection,
            cardInstanceId: 'card_24:1',
          ),
        ),
        engineError('INVALID_INSPECTION_DEFENSE'),
      );
    },
  );

  test('invalid phase and ineligible actor are rejected', () {
    final state = scenarioState(base, {});
    expect(
      () => basicObserve(
        state.copyWith(phase: TurnPhase.turnStart),
        'player-1',
        'player-2',
      ),
      engineError('INVALID_PHASE'),
    );
    final cornered = state.copyWith(
      players: {
        ...state.players,
        'player-1': state.players['player-1']!.copyWith(
          status: PlayerStatus.cornered,
          hearts: 0,
        ),
      },
    );
    expect(
      () => basicObserve(cornered, 'player-1', 'player-2'),
      engineError('NOT_ELIGIBLE'),
    );
  });

  test('Check Alibi grants Clue without an action to reveal', () {
    final state = scenarioState(base, {
      'players': {
        'player-1': {
          'hand': ['card_12:1'],
        },
      },
    });
    final outcome = playInvestigation(
      state,
      actorPlayerId: 'player-1',
      targetPlayerId: 'player-2',
      cardInstanceId: 'card_12:1',
      random: SequenceRandom([]),
    );
    expect(outcome.revealedActionCardInstanceId, isNull);
    expect(outcome.evidenceAdded, isTrue);
    expect(outcome.state.version, state.version + 1);
    expect(
      outcome.state.players['player-1']!.lastPlayedActionCardInstanceId,
      'card_12:1',
    );
  });
}
