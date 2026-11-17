import 'attacks.dart';
import 'action_cards.dart';
import 'card_catalog.dart';
import 'cornered.dart';
import 'game_state.dart';
import 'turns.dart';

enum _PublicPhase {
  corneredResolution('cornered_resolution');

  const _PublicPhase(this.wireValue);
  final String wireValue;
}

class PublicPlayerView {
  const PublicPlayerView({
    required this.playerId,
    required this.status,
    required this.hearts,
    required this.suspicion,
    required this.handCount,
    required this.revealedRole,
  });

  final String playerId;
  final PlayerStatus status;
  final int hearts;
  final int suspicion;
  final int handCount;
  final PlayerRole? revealedRole;

  Map<String, Object?> toJson() => {
    'playerId': playerId,
    'status': status.name,
    'hearts': hearts,
    'suspicion': suspicion,
    'handCount': handCount,
    'revealedRole': revealedRole?.name,
  };
}

class PublicAttackView {
  const PublicAttackView({
    required this.attackerPlayerId,
    required this.targetPlayerId,
    required this.attackCardInstanceId,
    required this.calloutRevealedActionCardInstanceId,
  });

  final String attackerPlayerId;
  final String targetPlayerId;
  final String attackCardInstanceId;
  final String? calloutRevealedActionCardInstanceId;

  Map<String, Object?> toJson() => {
    'attackerPlayerId': attackerPlayerId,
    'targetPlayerId': targetPlayerId,
    'attackCardInstanceId': attackCardInstanceId,
    'calloutRevealedActionCardInstanceId': calloutRevealedActionCardInstanceId,
  };
}

class PublicCardEffectView {
  const PublicCardEffectView({
    required this.kind,
    required this.actorPlayerId,
    required this.targetPlayerIds,
  });

  final String kind;
  final String actorPlayerId;
  final List<String> targetPlayerIds;

  Map<String, Object?> toJson() => {
    'kind': kind,
    'actorPlayerId': actorPlayerId,
    'targetPlayerIds': targetPlayerIds,
  };
}

class PublicMatchView {
  const PublicMatchView({
    required this.matchId,
    required this.rulesVersion,
    required this.catalogVersion,
    required this.phase,
    required this.currentPlayerId,
    required this.corneredTargetPlayerId,
    required this.actionsRemaining,
    required this.attacksUsedThisTurn,
    required this.seatOrder,
    required this.players,
    required this.drawCount,
    required this.discardCount,
    required this.attack,
    required this.cardEffect,
    required this.activeEffects,
    required this.publicActionHistory,
    required this.winner,
  });

  final String matchId;
  final String rulesVersion;
  final String catalogVersion;
  final String phase;
  final String? currentPlayerId;
  final String? corneredTargetPlayerId;
  final int actionsRemaining;
  final int attacksUsedThisTurn;
  final List<String> seatOrder;
  final Map<String, PublicPlayerView> players;
  final int drawCount;
  final int discardCount;
  final PublicAttackView? attack;
  final PublicCardEffectView? cardEffect;
  final List<SafePlaceEffect> activeEffects;
  final List<PublicAction> publicActionHistory;
  final MatchOutcome? winner;

  Map<String, Object?> toJson() => {
    'matchId': matchId,
    'rulesVersion': rulesVersion,
    'catalogVersion': catalogVersion,
    'phase': phase,
    'currentPlayerId': currentPlayerId,
    'corneredTargetPlayerId': corneredTargetPlayerId,
    'actionsRemaining': actionsRemaining,
    'attacksUsedThisTurn': attacksUsedThisTurn,
    'seatOrder': seatOrder,
    'players': players.map((id, player) => MapEntry(id, player.toJson())),
    'drawCount': drawCount,
    'discardCount': discardCount,
    'attack': attack?.toJson(),
    'cardEffect': cardEffect?.toJson(),
    'activeEffects': activeEffects.map((effect) => effect.toJson()).toList(),
    'publicActionHistory': publicActionHistory
        .map((action) => action.toJson())
        .toList(),
    'winner': winner?.toJson(),
  };
}

class PrivatePrompt {
  const PrivatePrompt._({
    required this.kind,
    this.targetPlayerId,
    this.deadlineUtc,
    this.canAccuse,
    this.canFinish,
    this.canPlay,
    this.submitted,
  });

  const PrivatePrompt.attackResponse() : this._(kind: 'attack_response');

  const PrivatePrompt.cardEffectDiscard() : this._(kind: 'card_effect_discard');

  const PrivatePrompt.accusation({
    required String targetPlayerId,
    required String deadlineUtc,
    required bool canAccuse,
    required bool submitted,
  }) : this._(
         kind: 'accusation',
         targetPlayerId: targetPlayerId,
         deadlineUtc: deadlineUtc,
         canAccuse: canAccuse,
         submitted: submitted,
       );

  const PrivatePrompt.secretChoice({
    required String deadlineUtc,
    required bool canFinish,
    required bool submitted,
  }) : this._(
         kind: 'secret_choice',
         deadlineUtc: deadlineUtc,
         canFinish: canFinish,
         submitted: submitted,
       );

  const PrivatePrompt.lastChance({
    required String deadlineUtc,
    required bool canPlay,
    required bool submitted,
  }) : this._(
         kind: 'last_chance',
         deadlineUtc: deadlineUtc,
         canPlay: canPlay,
         submitted: submitted,
       );

  final String kind;
  final String? targetPlayerId;
  final String? deadlineUtc;
  final bool? canAccuse;
  final bool? canFinish;
  final bool? canPlay;
  final bool? submitted;

  Map<String, Object?> toJson() => {
    'kind': kind,
    if (targetPlayerId != null) 'targetPlayerId': targetPlayerId,
    if (deadlineUtc != null) 'deadlineUtc': deadlineUtc,
    if (canAccuse != null) 'canAccuse': canAccuse,
    if (canFinish != null) 'canFinish': canFinish,
    if (canPlay != null) 'canPlay': canPlay,
    if (submitted != null) 'submitted': submitted,
  };
}

class PlayerSelfView {
  const PlayerSelfView({
    required this.playerId,
    required this.role,
    required this.hand,
    required this.evidence,
    required this.accusationUsed,
    required this.prompt,
  });

  final String playerId;
  final PlayerRole? role;
  final List<String> hand;
  final Map<String, Evidence> evidence;
  final bool accusationUsed;
  final PrivatePrompt? prompt;

  Map<String, Object?> toJson() => {
    'playerId': playerId,
    'role': role?.name,
    'hand': hand,
    'evidence': evidence.map((id, value) => MapEntry(id, value.toJson())),
    'accusationUsed': accusationUsed,
    'prompt': prompt?.toJson(),
  };
}

class PlayerMatchView {
  const PlayerMatchView({required this.public, required this.self});

  final PublicMatchView public;
  final PlayerSelfView self;

  Map<String, Object?> toJson() => {
    'public': public.toJson(),
    'self': self.toJson(),
  };
}

PublicMatchView projectPublicState(MatchState state) {
  final isCorneredResolution =
      state.phase == TurnPhase.awaitingAccusation ||
      state.phase == TurnPhase.awaitingSecretFinish ||
      state.phase == TurnPhase.awaitingLastChance;
  final phase = isCorneredResolution
      ? _PublicPhase.corneredResolution.wireValue
      : state.phase.wireValue;
  final players = <String, PublicPlayerView>{};
  for (final id in state.seatOrder) {
    final player = state.players[id];
    if (player == null) {
      throw const EngineException(
        'INVALID_PLAYER',
        'A seat is missing its player state',
      );
    }
    final revealedAtFinish =
        state.phase == TurnPhase.finished &&
        state.winner?.kind == 'winner' &&
        (state.winner!.playerId == id || player.role == PlayerRole.impostor);
    players[id] = PublicPlayerView(
      playerId: id,
      status: player.status,
      hearts: player.hearts,
      suspicion: player.suspicion,
      handCount: player.hand.length,
      revealedRole: player.status == PlayerStatus.eliminated || revealedAtFinish
          ? player.role
          : null,
    );
  }
  final pendingAttack = state.pendingAttack;
  final attack =
      state.phase == TurnPhase.awaitingReaction && pendingAttack != null
      ? PublicAttackView(
          attackerPlayerId: pendingAttack.attackerPlayerId,
          targetPlayerId: pendingAttack.targetPlayerId,
          attackCardInstanceId: pendingAttack.attackCardInstanceId,
          calloutRevealedActionCardInstanceId:
              pendingAttack.calloutRevealedActionCardInstanceId,
        )
      : null;
  final pendingCardEffect = state.pendingCardEffect;
  final cardEffect =
      state.phase == TurnPhase.awaitingCardEffect && pendingCardEffect != null
      ? PublicCardEffectView(
          kind: pendingCardEffect.kind,
          actorPlayerId: pendingCardEffect.actorPlayerId,
          targetPlayerIds: pendingCardEffect.kind == 'stir_the_pot_discards'
              ? [...pendingCardEffect.targetPlayerIds]
              : [],
        )
      : null;

  return PublicMatchView(
    matchId: state.matchId,
    rulesVersion: rulesVersion,
    catalogVersion: catalogVersion,
    phase: phase,
    currentPlayerId: state.currentPlayerId,
    corneredTargetPlayerId: isCorneredResolution
        ? state.pendingCornered?.targetPlayerId
        : null,
    actionsRemaining: state.actionsRemaining,
    attacksUsedThisTurn: state.attacksUsedThisTurn,
    seatOrder: [...state.seatOrder],
    players: players,
    drawCount: state.drawPile.length,
    discardCount: state.discardPile.length,
    attack: attack,
    cardEffect: cardEffect,
    activeEffects: state.activeEffects
        .map(
          (effect) => SafePlaceEffect(
            casterPlayerId: effect.casterPlayerId,
            targetPlayerId: effect.targetPlayerId,
          ),
        )
        .toList(),
    publicActionHistory: state.publicActionHistory
        .map(
          (action) =>
              PublicAction(playerId: action.playerId, kind: action.kind),
        )
        .toList(),
    winner: state.winner == null
        ? null
        : state.winner!.kind == 'winner'
        ? MatchOutcome.winner(state.winner!.playerId!)
        : const MatchOutcome.cancelled(),
  );
}

PlayerMatchView projectPlayerState(MatchState state, String playerId) {
  final player = state.players[playerId];
  if (player == null || !state.seatOrder.contains(playerId)) {
    throw const EngineException(
      'INVALID_PLAYER',
      'The player must belong to the match',
    );
  }
  PrivatePrompt? prompt;
  if (currentAttackResponder(state) == playerId) {
    prompt = const PrivatePrompt.attackResponse();
  } else if (currentCardEffectResponder(state) == playerId) {
    prompt = const PrivatePrompt.cardEffectDiscard();
  } else if (currentAccusationPlayerId(state) == playerId &&
      player.status == PlayerStatus.active &&
      state.pendingCornered != null &&
      state.deadlineUtc != null) {
    prompt = PrivatePrompt.accusation(
      targetPlayerId: state.pendingCornered!.targetPlayerId,
      deadlineUtc: state.deadlineUtc!,
      canAccuse: isEligibleAccuser(
        state,
        playerId,
        state.pendingCornered!.targetPlayerId,
      ),
      submitted: state.pendingCornered!.accusationPassed,
    );
  } else if (state.phase == TurnPhase.awaitingSecretFinish &&
      state.pendingSecretFinish?.eligiblePlayerIds.contains(playerId) == true &&
      state.deadlineUtc != null) {
    prompt = PrivatePrompt.secretChoice(
      deadlineUtc: state.deadlineUtc!,
      canFinish: player.role == PlayerRole.impostor,
      submitted: state.pendingSecretFinish!.submissions.containsKey(playerId),
    );
  } else if (currentLastChancePlayerId(state) == playerId &&
      state.pendingCornered != null &&
      state.deadlineUtc != null) {
    prompt = PrivatePrompt.lastChance(
      deadlineUtc: state.deadlineUtc!,
      canPlay: player.hand.any(
        (card) =>
            RegExp(r'^(card_\d{2}):[1-9]\d*$').firstMatch(card)?.group(1) ==
            'card_19',
      ),
      submitted: state.pendingCornered!.lastChanceChoice != null,
    );
  }

  return PlayerMatchView(
    public: projectPublicState(state),
    self: PlayerSelfView(
      playerId: playerId,
      role: player.role,
      hand: [...player.hand],
      evidence: {
        for (final entry in player.evidence.entries)
          entry.key: Evidence(
            clue: entry.value.clue,
            behavior: entry.value.behavior,
          ),
      },
      accusationUsed: player.accusationUsed,
      prompt: prompt,
    ),
  );
}
