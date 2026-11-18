import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:fibpop_mobile/engine/action_cards.dart';
import 'package:fibpop_mobile/engine/attacks.dart';
import 'package:fibpop_mobile/engine/cornered.dart';
import 'package:fibpop_mobile/engine/departures.dart';
import 'package:fibpop_mobile/engine/game_state.dart';
import 'package:fibpop_mobile/engine/investigations.dart';
import 'package:fibpop_mobile/engine/projections.dart';
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

bool _hasPath(Map<String, Object?> value, String path) {
  Object? current = value;
  for (final part in path.split('.')) {
    if (current is! Map || !current.containsKey(part)) return false;
    current = current[part];
  }
  return true;
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
  double next() {
    if (index >= values.length) {
      throw StateError('Fixture random sequence exhausted');
    }
    return values[index++];
  }
}

class FixtureStepOutcome {
  const FixtureStepOutcome(this.state, [this.result = const {}]);

  final MatchState state;
  final Map<String, Object?> result;
}

FixtureStepOutcome executeScenarioCommand(
  MatchState state,
  Map<String, Object?> command,
) {
  switch (command['type']) {
    case 'ATTACK':
      return FixtureStepOutcome(
        startAttack(
          state,
          command['actor'] as String,
          command['target'] as String,
          command['card'] as String,
        ),
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
      return FixtureStepOutcome(
        respondToAttack(
          state,
          command['actor'] as String,
          parsed,
          nowMs: command['nowMs'] as int,
        ),
      );
    case 'INVESTIGATE':
      final rawDefense = command['defense'];
      InvestigationDefense? defense;
      if (rawDefense != null) {
        final value = object(rawDefense);
        defense = InvestigationDefense(
          kind: InvestigationDefenseKind.values.byName(value['kind'] as String),
          cardInstanceId: value['cardInstanceId'] as String,
        );
      }
      final outcome = playInvestigation(
        state,
        actorPlayerId: command['actor'] as String,
        targetPlayerId: command['target'] as String,
        cardInstanceId: command['card'] as String,
        random: _random(command),
        defense: defense,
      );
      return FixtureStepOutcome(outcome.state, outcome.resultToJson());
    case 'PLAY_CARD':
      return _playCard(state, command);
    case 'DISCARD':
      final outcome = respondToCardEffectDiscard(
        state,
        command['actor'] as String,
        command['card'] as String,
      );
      return FixtureStepOutcome(outcome.state, {
        'nextResponderPlayerId': outcome.nextResponderPlayerId,
      });
    case 'BASIC_OBSERVE':
      final outcome = basicObserve(
        state,
        command['actor'] as String,
        command['target'] as String,
      );
      return FixtureStepOutcome(outcome.state, {
        'evidenceAdded': outcome.evidenceAdded,
      });
    case 'ACCUSE':
      final response = switch (command['response']) {
        'pass' => const AccusationResponse.pass(),
        'accuse' => const AccusationResponse.accuse(),
        _ => throw StateError('Unknown accusation response'),
      };
      return FixtureStepOutcome(
        respondToAccusation(
          state,
          command['actor'] as String,
          response,
          command['nowMs'] as int,
        ),
      );
    case 'EXPIRE_ACCUSATION':
      return FixtureStepOutcome(
        expireAccusationOffer(state, command['nowMs'] as int),
      );
    case 'SECRET_CHOICE':
      return FixtureStepOutcome(
        submitSecretFinishChoice(
          state,
          command['actor'] as String,
          command['choice'] as String,
          command['nowMs'] as int,
        ),
      );
    case 'EXPIRE_SECRET':
      return FixtureStepOutcome(
        expireSecretFinishWindow(state, command['nowMs'] as int),
      );
    case 'PLAY_LAST_CHANCE':
      return FixtureStepOutcome(
        playLastChance(
          state,
          command['actor'] as String,
          command['card'] as String,
          command['nowMs'] as int,
        ),
      );
    case 'PASS_LAST_CHANCE':
      return FixtureStepOutcome(
        passLastChance(
          state,
          command['actor'] as String,
          command['nowMs'] as int,
        ),
      );
    case 'EXPIRE_LAST_CHANCE':
      return FixtureStepOutcome(
        expireLastChanceWindow(state, command['nowMs'] as int),
      );
    case 'DEPARTURE':
      final departure = object(command['departure']);
      final parsed = switch (departure['kind']) {
        'disconnect' => const DisconnectDeparture(),
        'forfeit' => ForfeitDeparture(departure['nowMs'] as int),
        _ => throw StateError('Unknown player departure'),
      };
      return FixtureStepOutcome(
        handlePlayerDeparture(state, command['actor'] as String, parsed),
      );
    case 'END_TURN':
      return FixtureStepOutcome(
        endTurn(state, (command['discards'] as List).cast<String>()),
      );
    case 'BEGIN_TURN':
      return FixtureStepOutcome(beginTurn(state, _random(command)));
    default:
      throw StateError('Unsupported fixture command: ${command['type']}');
  }
}

RandomSource _random(Map<String, Object?> command) => FixtureRandom(
  (command['randomSequence'] as List)
      .map((value) => (value as num).toDouble())
      .toList(),
);

FixtureStepOutcome _playCard(MatchState state, Map<String, Object?> command) {
  final actor = command['actor'] as String;
  final card = command['card'] as String;
  final target = command['target'] as String?;
  final targets = (command['targets'] as List?)?.cast<String>() ?? const [];
  final random = _random(command);
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
    case 'card_21':
      return FixtureStepOutcome(playSafePlace(state, actor, target!, card));
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
  final scenarios = (suite['scenarios'] as List).map(object).toList();

  for (final scenario in scenarios) {
    test('shared gameplay parity: ${scenario['name']}', () {
      var state = scenarioState(base, object(scenario['initialState']));
      for (final rawStep in scenario['steps'] as List) {
        final step = object(rawStep);
        final command = object(step['command']);
        if (step['expectedError'] != null) {
          final before = state.toJson();
          expect(
            () => executeScenarioCommand(state, command),
            engineError(step['expectedError'] as String),
            reason: scenario['name'] as String,
          );
          expect(state.toJson(), before);
          continue;
        }

        final outcome = executeScenarioCommand(state, command);
        state = outcome.state;
        if (step['expectedResult'] != null) {
          expectSubset(
            outcome.result,
            step['expectedResult'],
            '${scenario['name']}.result',
          );
        }
        if (step['expectedPublic'] != null) {
          expectSubset(
            projectPublicState(state).toJson(),
            step['expectedPublic'],
            '${scenario['name']}.public',
          );
        }
        for (final path in (step['absentPublicPaths'] as List? ?? const [])) {
          expect(
            _hasPath(projectPublicState(state).toJson(), path as String),
            isFalse,
            reason: '${scenario['name']}.public.$path',
          );
        }
        if (step['expectedPrivate'] != null) {
          final privateViews = object(step['expectedPrivate']);
          for (final entry in privateViews.entries) {
            expectSubset(
              projectPlayerState(state, entry.key).toJson(),
              entry.value,
              '${scenario['name']}.private.${entry.key}',
            );
          }
        }
      }
      expectSubset(
        state.toJson(),
        scenario['expectedState'],
        scenario['name'] as String,
      );
    });
  }
}
