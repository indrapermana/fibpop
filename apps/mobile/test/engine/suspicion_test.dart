import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:fibpop_mobile/engine/game_state.dart';
import 'package:fibpop_mobile/engine/random.dart';
import 'package:fibpop_mobile/engine/suspicion.dart';
import 'package:fibpop_mobile/engine/turns.dart';

class FixtureRandom implements RandomSource {
  FixtureRandom(this.value);

  final double value;

  @override
  double next() => value;
}

Map<String, Object?> object(Object? value) =>
    (value as Map).cast<String, Object?>();

void main() {
  final setupFixture = object(
    jsonDecode(
      File(
        '../../shared/fixtures/m1-deterministic-setup.json',
      ).readAsStringSync(),
    ),
  );
  final turnFixture = object(
    jsonDecode(
      File(
        '../../shared/fixtures/m1-turn-start-recycle.json',
      ).readAsStringSync(),
    ),
  );

  MatchState activeTurn() {
    final initial = MatchState.fromJson(object(turnFixture['initialState']));
    final values = (turnFixture['randomSequence'] as List)
        .map((value) => (value as num).toDouble())
        .toList();
    var index = 0;
    return beginTurn(initial, _SequenceRandom(values, () => index++));
  }

  test('clamps Suspicion adjustment without mutating state', () {
    final state = MatchState.fromJson(object(setupFixture['expectedState']));
    final atMaximum = adjustSuspicion(state, 'player-1', 10);
    final atMinimum = adjustSuspicion(atMaximum, 'player-1', -10);
    expect(atMaximum.players['player-1']!.suspicion, 3);
    expect(atMinimum.players['player-1']!.suspicion, 0);
    expect(state.players['player-1']!.suspicion, 0);
    expect(
      () => adjustSuspicion(state, 'missing-player', 1),
      engineError('INVALID_PLAYER'),
    );
    expect(
      () => adjustSuspicion(state, 'player-1', 0.5),
      engineError('INVALID_SUSPICION_CHANGE'),
    );
    expect(
      () => adjustSuspicion(state, 'player-1', double.infinity),
      engineError('INVALID_SUSPICION_CHANGE'),
    );
  });

  test('records Noisy manipulation after its action is spent', () {
    final state = activeTurn();
    final actor = state.currentPlayerId!;
    final spent = spendAction(state, TurnActionKind.action);
    final result = recordNoisyManipulation(spent, actor);
    expect(result.players[actor]!.suspicion, 1);
    expect(result.actionsRemaining, 1);
    expect(result.publicActionHistory.last.toJson(), {
      'playerId': actor,
      'kind': 'noisy_manipulation',
    });
    expect(hasBehaviorEvidenceQualifyingAction(result, actor), isTrue);
    expect(hasBehaviorEvidenceQualifyingAction(result, 'player-2'), isFalse);
    expect(state.publicActionHistory, isEmpty);
    final otherPlayer = state.seatOrder.firstWhere((id) => id != actor);
    expect(
      () => recordNoisyManipulation(result, otherPlayer),
      engineError('NOT_YOUR_TURN'),
    );
  });

  test(
    'Noisy manipulation caps at 3 and rejects phase or actor violations',
    () {
      final state = activeTurn();
      final actor = state.currentPlayerId!;
      final player = state.players[actor]!;
      final capped = state.copyWith(
        players: {...state.players, actor: player.copyWith(suspicion: 3)},
      );
      final result = recordNoisyManipulation(
        spendAction(capped, TurnActionKind.action),
        actor,
      );
      expect(result.players[actor]!.suspicion, 3);
      expect(result.publicActionHistory, hasLength(1));
      expect(
        () => recordNoisyManipulation(
          state.copyWith(phase: TurnPhase.turnStart),
          actor,
        ),
        engineError('INVALID_ACTION_PHASE'),
      );
      expect(
        () => recordNoisyManipulation(state, 'player-2'),
        engineError('NOT_YOUR_TURN'),
      );
      final cornered = state.copyWith(
        players: {
          ...state.players,
          actor: player.copyWith(status: PlayerStatus.cornered, hearts: 0),
        },
      );
      expect(
        () => recordNoisyManipulation(cornered, actor),
        engineError('NOT_ELIGIBLE'),
      );
    },
  );

  test(
    'successful damage awards Suspicion once and records qualifying history',
    () {
      final state = activeTurn();
      final attacker = state.currentPlayerId!;
      final attack = spendAction(state, TurnActionKind.attack);
      final result = recordSuccessfulAttackDamage(attack, attacker);
      expect(result.players[attacker]!.suspicion, 1);
      expect(result.suspicionAwardedForDamageThisTurn, isTrue);
      expect(result.publicActionHistory.last.toJson(), {
        'playerId': attacker,
        'kind': 'successful_attack',
      });
      expect(hasBehaviorEvidenceQualifyingAction(result, attacker), isTrue);
      expect(
        () => recordSuccessfulAttackDamage(result, attacker),
        engineError('DUPLICATE_ATTACK_RECORD'),
      );
      final nextTurn = beginTurn(endTurn(result, []), FixtureRandom(0));
      expect(nextTurn.suspicionAwardedForDamageThisTurn, isFalse);
      expect(nextTurn.publicActionHistory, result.publicActionHistory);
      expect(state.publicActionHistory, isEmpty);
    },
  );

  test(
    'damage requires the current player attack and does not exceed Suspicion cap',
    () {
      final state = activeTurn();
      final attacker = state.currentPlayerId!;
      expect(
        () => recordSuccessfulAttackDamage(state, attacker),
        engineError('INVALID_ACTION_PHASE'),
      );
      final capped = state.copyWith(
        players: {
          ...state.players,
          attacker: state.players[attacker]!.copyWith(suspicion: 3),
        },
      );
      final result = recordSuccessfulAttackDamage(
        spendAction(capped, TurnActionKind.attack),
        attacker,
      );
      expect(result.players[attacker]!.suspicion, 3);
    },
  );
}

Matcher engineError(String code) =>
    throwsA(isA<EngineException>().having((error) => error.code, 'code', code));

class _SequenceRandom implements RandomSource {
  _SequenceRandom(this.values, this.nextIndex);

  final List<double> values;
  final int Function() nextIndex;

  @override
  double next() {
    final index = nextIndex();
    if (index >= values.length) {
      throw StateError('Fixture random sequence exhausted');
    }
    return values[index];
  }
}
