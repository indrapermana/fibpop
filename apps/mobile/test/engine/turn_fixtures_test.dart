import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:fibpop_mobile/engine/card_catalog.dart';
import 'package:fibpop_mobile/engine/game_state.dart';
import 'package:fibpop_mobile/engine/random.dart';
import 'package:fibpop_mobile/engine/setup.dart';
import 'package:fibpop_mobile/engine/turns.dart';

class FixtureRandom implements RandomSource {
  FixtureRandom(this.values);
  final List<double> values;
  var index = 0;

  @override
  double next() {
    if (values.isEmpty) throw StateError('Fixture random sequence is empty');
    final value = values[index % values.length];
    index++;
    return value;
  }
}

Map<String, Object?> readJson(String path) =>
    jsonDecode(File(path).readAsStringSync()) as Map<String, Object?>;

Map<String, Object?> object(Object? value) => value as Map<String, Object?>;

List<double> randomValues(Object? value) =>
    (value as List).map((value) => (value as num).toDouble()).toList();

void main() {
  final catalog = CardCatalog.fromJson(
    readJson('../../shared/card_catalog_v1.json'),
  );
  final setupFixture = readJson(
    '../../shared/fixtures/m1-deterministic-setup.json',
  );
  final beginFixture = readJson(
    '../../shared/fixtures/m1-turn-start-recycle.json',
  );
  final endFixture = readJson(
    '../../shared/fixtures/m1-end-turn-recovery.json',
  );

  test('matches the complete shared deterministic setup fixture', () {
    final input = object(setupFixture['setup']);
    final result = createMatch(
      matchId: input['matchId'] as String,
      playerIds: (input['playerIds'] as List).cast<String>(),
      catalog: catalog,
      random: FixtureRandom(randomValues(input['randomSequence'])),
    );
    expect(
      result.toJson(),
      MatchState.fromJson(object(setupFixture['expectedState'])).toJson(),
    );
  });

  test('matches shared turn-start recycling without mutating its input', () {
    final initial = MatchState.fromJson(object(beginFixture['initialState']));
    final before = initial.toJson();
    final result = beginTurn(
      initial,
      FixtureRandom(randomValues(beginFixture['randomSequence'])),
    );
    expect(
      result.toJson(),
      MatchState.fromJson(object(beginFixture['expectedState'])).toJson(),
    );
    expect(initial.toJson(), before);
  });

  test('matches shared turn-end discard and Cornered recovery', () {
    final initial = MatchState.fromJson(object(endFixture['initialState']));
    final before = initial.toJson();
    final result = endTurn(
      initial,
      (endFixture['discardCardInstanceIds'] as List).cast<String>(),
    );
    expect(
      result.toJson(),
      MatchState.fromJson(object(endFixture['expectedState'])).toJson(),
    );
    expect(initial.toJson(), before);
  });

  test('rejects invalid setup and random values', () {
    expect(
      () => createMatch(
        matchId: 'x',
        playerIds: ['a', 'b', 'c'],
        catalog: catalog,
        random: FixtureRandom([0]),
      ),
      throwsArgumentError,
    );
    expect(
      () => createMatch(
        matchId: 'x',
        playerIds: ['a', 'b', 'c', 'd'],
        catalog: catalog,
        random: FixtureRandom([1]),
      ),
      throwsRangeError,
    );
    final eight = createMatch(
      matchId: 'eight',
      playerIds: List.generate(8, (index) => 'p$index'),
      catalog: catalog,
      random: FixtureRandom([0.5]),
    );
    final cards = [
      ...eight.drawPile,
      ...eight.players.values.expand((player) => player.hand),
    ];
    expect(cards.toSet().length, 72);
    expect(
      eight.players.values
          .where((player) => player.role == PlayerRole.impostor)
          .length,
      1,
    );
    expect(eight.drawPile.length, 40);
  });

  test('rejects invalid catalogs and unknown state fields', () {
    final catalogJson = readJson('../../shared/card_catalog_v1.json');
    expect(
      () => CardCatalog.fromJson({...catalogJson, 'unexpected': true}),
      throwsFormatException,
    );
    final sourceCards = catalogJson['cards'] as List;
    final cards = [
      for (final card in sourceCards) {...object(card)},
    ];
    cards[0]['copies'] = 1;
    expect(
      () => CardCatalog.fromJson({...catalogJson, 'cards': cards}),
      throwsFormatException,
    );
    expect(
      () => MatchState.fromJson({
        ...object(beginFixture['initialState']),
        'unexpected': true,
      }),
      throwsFormatException,
    );
  });

  test('does not expose mutable state collections', () {
    final state = MatchState.fromJson(object(beginFixture['initialState']));
    expect(() => state.drawPile.add('extra'), throwsUnsupportedError);
    expect(() => state.players.clear(), throwsUnsupportedError);
    expect(
      () => state.players['player-1']!.hand.add('extra'),
      throwsUnsupportedError,
    );
  });

  test('rejects invalid discards without changing state', () {
    final initial = MatchState.fromJson(object(endFixture['initialState']));
    final before = initial.toJson();
    expect(
      () => endTurn(initial, []),
      throwsA(
        isA<EngineException>().having(
          (error) => error.code,
          'code',
          'INVALID_DISCARD_COUNT',
        ),
      ),
    );
    expect(
      () => endTurn(initial, ['not-owned']),
      throwsA(
        isA<EngineException>().having(
          (error) => error.code,
          'code',
          'INVALID_DISCARD',
        ),
      ),
    );
    expect(initial.toJson(), before);
  });

  test('enforces action and attack limits', () {
    final initial = MatchState.fromJson(object(beginFixture['initialState']));
    final active = beginTurn(initial, FixtureRandom([0.2]));
    final attacked = spendAction(active, TurnActionKind.attack);
    expect(
      () => spendAction(attacked, TurnActionKind.attack),
      throwsA(
        isA<EngineException>().having(
          (error) => error.code,
          'code',
          'ATTACK_LIMIT',
        ),
      ),
    );
    final spent = spendAction(attacked, TurnActionKind.action);
    expect(
      () => spendAction(spent, TurnActionKind.action),
      throwsA(
        isA<EngineException>().having(
          (error) => error.code,
          'code',
          'NO_ACTIONS_REMAIN',
        ),
      ),
    );
    expect(active.actionsRemaining, 2);
  });

  test('rejects malformed pending attack state', () {
    final json = object(beginFixture['initialState']);
    expect(
      () => MatchState.fromJson({
        ...json,
        'pendingAttack': {'attackerPlayerId': 'player-1'},
      }),
      throwsFormatException,
    );
  });

  test('rejects malformed pending card effect state', () {
    final json = object(beginFixture['initialState']);
    expect(
      () => MatchState.fromJson({
        ...json,
        'pendingCardEffect': {'kind': 'catch_your_breath_discard'},
      }),
      throwsFormatException,
    );
  });
}
