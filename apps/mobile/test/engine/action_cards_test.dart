import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:fibpop_mobile/engine/action_cards.dart';
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

class FixtureRandom implements RandomSource {
  FixtureRandom(this.values);

  final List<double> values;
  var index = 0;

  @override
  double next() => index < values.length ? values[index++] : 0;
}

class FixtureStepOutcome {
  const FixtureStepOutcome(this.state, [this.result = const {}]);

  final MatchState state;
  final Map<String, Object?> result;
}

FixtureStepOutcome executeCardStep(
  MatchState state,
  Map<String, Object?> command,
) {
  final actor = command['actor'] as String;
  if (command['type'] == 'DISCARD') {
    final outcome = respondToCardEffectDiscard(
      state,
      actor,
      command['card'] as String,
    );
    return FixtureStepOutcome(outcome.state, {
      'nextResponderPlayerId': outcome.nextResponderPlayerId,
    });
  }
  if (command['type'] != 'PLAY_CARD') {
    throw StateError('Unsupported action-card command: ${command['type']}');
  }

  final card = command['card'] as String;
  final target = command['target'] as String?;
  final targets = (command['targets'] as List?)?.cast<String>() ?? const [];
  final randomValues = (command['randomSequence'] as List)
      .map((value) => (value as num).toDouble())
      .toList();
  final random = FixtureRandom(randomValues);
  switch (card.substring(0, 7)) {
    case 'card_13':
      return FixtureStepOutcome(playPointFingers(state, actor, target!, card));
    case 'card_14':
      return FixtureStepOutcome(playCleanSlate(state, actor, card));
    case 'card_15':
      return FixtureStepOutcome(playStirThePot(state, actor, targets, card));
    case 'card_16':
      final outcome = playCardSwap(state, actor, target!, card, random);
      return FixtureStepOutcome(outcome.state, {
        'privateResult': {
          'givenToTargetCardInstanceId': outcome.givenToTargetCardInstanceId,
          'receivedCardInstanceId': outcome.receivedCardInstanceId,
        },
      });
    case 'card_17':
      return FixtureStepOutcome(playFirstAid(state, actor, target!, card));
    case 'card_18':
      final outcome = playCatchYourBreath(state, actor, card, random);
      return FixtureStepOutcome(outcome.state, {
        'privateResult': {'drawnCardInstanceIds': outcome.drawnCardInstanceIds},
      });
    case 'card_20':
      return FixtureStepOutcome(playPatchUp(state, actor, card));
    case 'card_23':
      final outcome = playSpotlight(state, actor, card, random);
      return FixtureStepOutcome(outcome.state, {
        'publicResult': {'suspicionByPlayerId': outcome.suspicionByPlayerId},
        'privateResult': {'drawnCardInstanceId': outcome.drawnCardInstanceId},
      });
    default:
      throw StateError('Unsupported action card: $card');
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
    'point-fingers-suspicion-cap',
    'clean-slate-noisy-order',
    'stir-the-pot-clockwise',
    'card-swap-deterministic',
    'first-aid-revives-cornered',
    'catch-your-breath-draw-discard',
    'patch-up',
    'spotlight-public-suspicion-private-draw',
  };
  final scenarios = (suite['scenarios'] as List)
      .map(object)
      .where((scenario) => scenarioNames.contains(scenario['name']))
      .toList();

  test('matches shared scenarios for remaining action-card effects', () {
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
            () => executeCardStep(state, command),
            engineError(step['expectedError'] as String),
            reason: scenario['name'] as String,
          );
          expect(state.toJson(), before);
          continue;
        }
        final outcome = executeCardStep(state, command);
        state = outcome.state;
        expect(state.toJson(), isNot(before));
        expect(MatchState.fromJson(state.toJson()).toJson(), state.toJson());
        if (step['expectedResult'] != null) {
          expectSubset(
            outcome.result,
            step['expectedResult'],
            '${scenario['name']}.result',
          );
        }
      }
      expectSubset(
        state.toJson(),
        scenario['expectedState'],
        scenario['name'] as String,
      );
    }
  });
}
