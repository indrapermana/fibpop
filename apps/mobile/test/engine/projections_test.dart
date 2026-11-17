import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:fibpop_mobile/engine/action_cards.dart';
import 'package:fibpop_mobile/engine/attacks.dart';
import 'package:fibpop_mobile/engine/game_state.dart';
import 'package:fibpop_mobile/engine/projections.dart';

Map<String, Object?> object(Object? value) =>
    (value as Map).cast<String, Object?>();

MatchState scenarioState(
  Map<String, Object?> base,
  Map<String, Object?> overrides,
) {
  final players = Map<String, Object?>.from(object(base['players']));
  for (final entry in object(overrides['players'] ?? {}).entries) {
    players[entry.key] = {
      ...object(players[entry.key]),
      ...object(entry.value),
    };
  }
  return MatchState.fromJson({...base, ...overrides, 'players': players});
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

  test('reveals only the viewer private information and public state', () {
    final state = scenarioState(base, {
      'drawPile': ['private-draw-card'],
      'players': {
        'player-1': {
          'hand': ['card_19:1'],
          'evidence': {
            'player-2': {'clue': true, 'behavior': true},
          },
        },
        'player-3': {
          'hand': ['private-player-3-card'],
        },
      },
    });
    final view = projectPlayerState(state, 'player-1');
    final publicJson = jsonEncode(view.public.toJson());
    final fullJson = jsonEncode(view.toJson());

    expect(view.self.role, PlayerRole.innocent);
    expect(view.self.hand, ['card_19:1']);
    expect(view.self.evidence['player-2']!.clue, isTrue);
    expect(view.public.players['player-4']!.revealedRole, isNull);
    expect(publicJson, isNot(contains('impostor')));
    expect(fullJson, isNot(contains('private-player-3-card')));
    expect(fullJson, isNot(contains('private-draw-card')));
  });

  test('maps Cornered phases and supplies private accusation prompts', () {
    final state = scenarioState(base, {
      'phase': 'awaiting_accusation',
      'deadlineUtc': '2026-11-17T00:00:10.000Z',
      'pendingCornered': {
        'attackerPlayerId': 'player-1',
        'targetPlayerId': 'player-2',
        'attackCardInstanceId': 'card_01:1',
        'accusationOrderPlayerIds': ['player-1', 'player-3', 'player-4'],
        'accusationIndex': 0,
        'accusationPassed': false,
        'secretFinishResolved': false,
        'lastChanceChoice': null,
      },
      'players': {
        'player-1': {
          'evidence': {
            'player-2': {'clue': true, 'behavior': true},
          },
        },
        'player-2': {'status': 'cornered', 'hearts': 0},
      },
    });
    final view = projectPlayerState(state, 'player-1');
    expect(view.public.phase, 'cornered_resolution');
    expect(view.public.corneredTargetPlayerId, 'player-2');
    expect(view.self.prompt!.toJson(), {
      'kind': 'accusation',
      'targetPlayerId': 'player-2',
      'deadlineUtc': '2026-11-17T00:00:10.000Z',
      'canAccuse': true,
      'submitted': false,
    });
  });

  test('keeps sealed Secret Finish submissions out of public views', () {
    final cornered = scenarioState(base, {
      'phase': 'awaiting_secret_finish',
      'deadlineUtc': '2026-11-17T00:00:10.000Z',
      'pendingCornered': {
        'attackerPlayerId': 'player-1',
        'targetPlayerId': 'player-2',
        'attackCardInstanceId': 'card_01:1',
        'accusationOrderPlayerIds': [],
        'accusationIndex': 0,
        'accusationPassed': false,
        'secretFinishResolved': false,
        'lastChanceChoice': null,
      },
      'pendingSecretFinish': {
        'targetPlayerId': 'player-2',
        'eligiblePlayerIds': ['player-1', 'player-3', 'player-4'],
        'submissions': {'player-4': 'finish'},
      },
      'players': {
        'player-2': {'status': 'cornered', 'hearts': 0},
      },
    });
    final publicView = projectPublicState(cornered);
    final publicJson = jsonEncode(publicView.toJson());
    final ownView = projectPlayerState(cornered, 'player-4');

    expect(publicView.phase, 'cornered_resolution');
    expect(publicJson, isNot(contains('finish')));
    expect(projectPlayerState(cornered, 'player-1').self.prompt, isNotNull);
    expect(ownView.self.prompt!.toJson(), {
      'kind': 'secret_choice',
      'deadlineUtc': '2026-11-17T00:00:10.000Z',
      'canFinish': true,
      'submitted': true,
    });
  });

  test(
    'projects card-effect and attack prompts without leaking hand choices',
    () {
      final cardEffectState = scenarioState(base, {
        'players': {
          'player-1': {
            'hand': ['card_15:1'],
          },
          'player-2': {
            'hand': ['private-player-2-card'],
          },
          'player-3': {
            'hand': ['private-player-3-card'],
          },
        },
      });
      final cardEffect = playStirThePot(cardEffectState, 'player-1', [
        'player-3',
        'player-2',
      ], 'card_15:1');
      final cardEffectView = projectPlayerState(cardEffect, 'player-2');
      expect(cardEffectView.self.prompt!.kind, 'card_effect_discard');
      expect(cardEffectView.public.cardEffect!.targetPlayerIds, [
        'player-2',
        'player-3',
      ]);
      expect(
        jsonEncode(cardEffectView.public.toJson()),
        isNot(contains('private-player-2-card')),
      );

      final attackState = scenarioState(base, {
        'players': {
          'player-1': {
            'hand': ['card_02:1'],
          },
          'player-2': {
            'hand': ['private-discard-choice'],
          },
        },
      });
      final attack = startAttack(
        attackState,
        'player-1',
        'player-2',
        'card_02:1',
      );
      final passed = respondToAttack(
        attack,
        'player-2',
        const AttackResponse.pass(
          discardCardInstanceId: 'private-discard-choice',
        ),
      );
      final attackView = projectPlayerState(passed, 'player-3');
      expect(attackView.self.prompt!.kind, 'attack_response');
      expect(attackView.public.attack!.targetPlayerId, 'player-2');
      expect(
        jsonEncode(attackView.public.toJson()),
        isNot(contains('private-discard-choice')),
      );
    },
  );

  test(
    'returns detached mutable views and reveals roles only at termination',
    () {
      final state = scenarioState(base, {
        'players': {
          'player-1': {
            'hand': ['card_13:1'],
            'evidence': {
              'player-2': {'clue': true, 'behavior': true},
            },
          },
        },
      });
      final view = projectPlayerState(state, 'player-1');
      view.self.hand.add('changed');
      view.self.evidence['player-2'] = const Evidence(
        clue: false,
        behavior: false,
      );
      view.public.seatOrder.add('changed');
      view.public.players.remove('player-4');
      expect(state.players['player-1']!.hand, ['card_13:1']);
      expect(state.players['player-1']!.evidence['player-2']!.clue, isTrue);
      expect(state.seatOrder, hasLength(4));
      expect(state.players.containsKey('player-4'), isTrue);

      final finished = scenarioState(base, {
        'phase': 'finished',
        'currentPlayerId': null,
        'winner': {'kind': 'winner', 'playerId': 'player-1'},
      });
      final finalView = projectPublicState(finished);
      expect(finalView.players['player-1']!.revealedRole, PlayerRole.innocent);
      expect(finalView.players['player-4']!.revealedRole, PlayerRole.impostor);
      expect(finalView.players['player-2']!.revealedRole, isNull);
    },
  );
}
