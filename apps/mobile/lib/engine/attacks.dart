import 'game_state.dart';
import 'cornered.dart';
import 'investigations.dart';
import 'suspicion.dart';
import 'turns.dart';

enum AttackResponseKind { pass, defend, stepIn }

class AttackResponse {
  const AttackResponse.pass({this.discardCardInstanceId})
    : kind = AttackResponseKind.pass,
      cardInstanceId = null;
  const AttackResponse.defend(this.cardInstanceId)
    : kind = AttackResponseKind.defend,
      discardCardInstanceId = null;
  const AttackResponse.stepIn(this.cardInstanceId)
    : kind = AttackResponseKind.stepIn,
      discardCardInstanceId = null;

  final AttackResponseKind kind;
  final String? cardInstanceId;
  final String? discardCardInstanceId;
}

const _attackCards = {'card_01', 'card_02', 'card_03', 'card_04'};
const _defenseCards = {'card_05', 'card_06', 'card_08'};
final _cardInstance = RegExp(r'^(card_\d{2}):[1-9]\d*$');

String? _cardDesignId(String id) => _cardInstance.firstMatch(id)?.group(1);

String _requireCard(
  MatchState state,
  String playerId,
  String cardInstanceId,
  Set<String> designs,
) {
  final player = state.players[playerId];
  final design = _cardDesignId(cardInstanceId);
  if (player == null ||
      !player.hand.contains(cardInstanceId) ||
      design == null ||
      !designs.contains(design)) {
    throw const EngineException(
      'INVALID_CARD',
      'Card must be an eligible card in the player hand',
    );
  }
  return design;
}

void _requireActiveActor(MatchState state, String playerId) {
  if (state.phase != TurnPhase.activeTurn) {
    throw const EngineException(
      'INVALID_PHASE',
      'Attacks require the active turn',
    );
  }
  if (state.currentPlayerId != playerId) {
    throw const EngineException(
      'NOT_YOUR_TURN',
      'Only the current player may attack',
    );
  }
  final player = state.players[playerId];
  if (player == null ||
      player.status != PlayerStatus.active ||
      player.hearts < 1) {
    throw const EngineException('NOT_ELIGIBLE', 'The attacker must be Active');
  }
}

List<String> _buildStepInOrder(MatchState state, String targetPlayerId) {
  final targetIndex = state.seatOrder.indexOf(targetPlayerId);
  final responders = <String>[];
  for (var offset = 1; offset < state.seatOrder.length; offset++) {
    final id = state.seatOrder[(targetIndex + offset) % state.seatOrder.length];
    final player = state.players[id];
    if (player?.status == PlayerStatus.active && player!.hearts > 0) {
      responders.add(id);
    }
  }
  return responders;
}

MatchState startAttack(
  MatchState state,
  String attackerPlayerId,
  String targetPlayerId,
  String attackCardInstanceId,
) {
  _requireActiveActor(state, attackerPlayerId);
  if (state.actionsRemaining < 1) {
    throw const EngineException(
      'NO_ACTIONS_REMAIN',
      'No actions remain this turn',
    );
  }
  if (state.attacksUsedThisTurn >= 1) {
    throw const EngineException(
      'ATTACK_LIMIT',
      'Only one attack is allowed per turn',
    );
  }
  final target = state.players[targetPlayerId];
  if (targetPlayerId == attackerPlayerId ||
      target == null ||
      target.status != PlayerStatus.active ||
      target.hearts < 1) {
    throw const EngineException(
      'INVALID_TARGET',
      'Attack target must be another Active player',
    );
  }
  final design = _requireCard(
    state,
    attackerPlayerId,
    attackCardInstanceId,
    _attackCards,
  );
  final attacker = state.players[attackerPlayerId]!;
  final spent = spendAction(state, TurnActionKind.attack);
  final players = {
    ...spent.players,
    attackerPlayerId: attacker.copyWith(
      hand: attacker.hand
          .where((card) => card != attackCardInstanceId)
          .toList(),
      lastPlayedActionCardInstanceId: attackCardInstanceId,
    ),
  };
  final pending = PendingAttack(
    attackerPlayerId: attackerPlayerId,
    targetPlayerId: targetPlayerId,
    attackCardInstanceId: attackCardInstanceId,
    stepInPlayerIds: _buildStepInOrder(state, targetPlayerId),
    stepInIndex: -1,
    targetDiscardCardInstanceId: null,
    calloutRevealedActionCardInstanceId: design == 'card_03'
        ? target.lastPlayedActionCardInstanceId
        : null,
  );
  var next = spent.copyWith(
    phase: TurnPhase.awaitingReaction,
    players: players,
    discardPile: [...state.discardPile, attackCardInstanceId],
    pendingAttack: pending,
    clearPendingCornered: true,
    clearDeadlineUtc: true,
  );
  if (design == 'card_04' &&
      target.suspicion >= 2 &&
      hasBehaviorEvidenceQualifyingAction(state, targetPlayerId)) {
    next = grantEvidence(
      next,
      attackerPlayerId,
      targetPlayerId,
      EvidenceKind.behavior,
    ).copyWith(version: spent.version);
  }
  return next;
}

String? currentAttackResponder(MatchState state) {
  final pending = state.pendingAttack;
  if (state.phase != TurnPhase.awaitingReaction || pending == null) return null;
  if (pending.stepInIndex == -1) return pending.targetPlayerId;
  if (pending.stepInIndex >= pending.stepInPlayerIds.length) return null;
  return pending.stepInPlayerIds[pending.stepInIndex];
}

MatchState _resolveDamage(MatchState state, int? nowMs) {
  final pending = state.pendingAttack;
  if (pending == null) {
    throw const EngineException(
      'INVALID_REACTION',
      'There is no attack to resolve',
    );
  }
  final target = state.players[pending.targetPlayerId];
  if (target == null ||
      target.status != PlayerStatus.active ||
      target.hearts < 1) {
    throw const EngineException(
      'INVALID_TARGET',
      'The pending attack target is no longer Active',
    );
  }
  final shieldIndex = state.activeEffects.indexWhere(
    (effect) => effect.targetPlayerId == pending.targetPlayerId,
  );
  if (shieldIndex >= 0) {
    return state.copyWith(
      version: state.version + 1,
      phase: TurnPhase.activeTurn,
      activeEffects: [
        for (var i = 0; i < state.activeEffects.length; i++)
          if (i != shieldIndex) state.activeEffects[i],
      ],
      clearPendingAttack: true,
    );
  }
  final discard = pending.targetDiscardCardInstanceId;
  if (discard != null && !target.hand.contains(discard)) {
    throw const EngineException(
      'INVALID_DISCARD',
      'Selected Double Down card must remain in target hand',
    );
  }
  final hearts = target.hearts - 1;
  final cornered = hearts == 0;
  final players = {
    ...state.players,
    pending.targetPlayerId: target.copyWith(
      hearts: hearts,
      status: cornered ? PlayerStatus.cornered : PlayerStatus.active,
      hand: discard == null
          ? target.hand
          : target.hand.where((card) => card != discard).toList(),
    ),
  };
  PendingCornered? pendingCornered;
  if (cornered) {
    if (nowMs == null) {
      throw const EngineException(
        'INVALID_DEADLINE',
        'A timestamp is required to open the Cornered accusation window',
      );
    }
    pendingCornered = PendingCornered(
      attackerPlayerId: pending.attackerPlayerId,
      targetPlayerId: pending.targetPlayerId,
      attackCardInstanceId: pending.attackCardInstanceId,
      accusationOrderPlayerIds: const [],
      accusationIndex: 0,
      accusationPassed: false,
      secretFinishResolved: false,
      lastChanceChoice: null,
    );
  }
  final discarded = [...state.discardPile, if (discard != null) discard];
  var wounded = state.copyWith(
    phase: cornered ? TurnPhase.awaitingAccusation : TurnPhase.activeTurn,
    players: players,
    discardPile: discarded,
    clearPendingAttack: true,
    pendingCornered: pendingCornered,
    clearDeadlineUtc: !cornered,
  );
  final recorded = recordSuccessfulAttackDamage(
    wounded,
    pending.attackerPlayerId,
  );
  wounded = recorded.copyWith(version: state.version + 1);
  return cornered ? beginCorneredResolution(wounded, nowMs!) : wounded;
}

MatchState _resolveDefense(
  MatchState state,
  String defenderPlayerId,
  String cardInstanceId,
) {
  final pending = state.pendingAttack!;
  final design = _requireCard(
    state,
    defenderPlayerId,
    cardInstanceId,
    _defenseCards,
  );
  final defender = state.players[defenderPlayerId]!;
  final players = {
    ...state.players,
    defenderPlayerId: defender.copyWith(
      hand: defender.hand.where((card) => card != cardInstanceId).toList(),
      suspicion: design == 'card_06'
          ? (defender.suspicion - 1).clamp(0, 3).toInt()
          : defender.suspicion,
    ),
  };
  var defended = state.copyWith(
    version: state.version + 1,
    phase: TurnPhase.activeTurn,
    players: players,
    discardPile: [...state.discardPile, cardInstanceId],
    clearPendingAttack: true,
  );
  if (design == 'card_08' &&
      hasBehaviorEvidenceQualifyingAction(state, pending.attackerPlayerId)) {
    defended = grantEvidence(
      defended,
      defenderPlayerId,
      pending.attackerPlayerId,
      EvidenceKind.behavior,
    ).copyWith(version: state.version + 1);
  }
  return defended;
}

MatchState _resolveStepIn(
  MatchState state,
  String responderPlayerId,
  String cardInstanceId,
) {
  _requireCard(state, responderPlayerId, cardInstanceId, const {'card_07'});
  final responder = state.players[responderPlayerId]!;
  return state.copyWith(
    version: state.version + 1,
    phase: TurnPhase.activeTurn,
    players: {
      ...state.players,
      responderPlayerId: responder.copyWith(
        hand: responder.hand.where((card) => card != cardInstanceId).toList(),
      ),
    },
    discardPile: [...state.discardPile, cardInstanceId],
    clearPendingAttack: true,
  );
}

MatchState respondToAttack(
  MatchState state,
  String responderPlayerId,
  AttackResponse response, {
  int? nowMs,
}) {
  if (state.phase != TurnPhase.awaitingReaction ||
      state.pendingAttack == null) {
    throw const EngineException(
      'INVALID_PHASE',
      'Attack reactions require a pending attack',
    );
  }
  final pending = state.pendingAttack!;
  final expected = currentAttackResponder(state);
  if (expected == null) {
    throw const EngineException(
      'INVALID_REACTION',
      'There is no eligible responder',
    );
  }
  if (responderPlayerId != expected) {
    throw const EngineException(
      'NOT_YOUR_TURN',
      'Only the current attack responder may act',
    );
  }
  if (response.kind == AttackResponseKind.pass) {
    if (pending.stepInIndex == -1) {
      final attackDesign = _cardDesignId(pending.attackCardInstanceId);
      final target = state.players[pending.targetPlayerId]!;
      final discard = response.discardCardInstanceId;
      if (attackDesign != 'card_02' && discard != null) {
        throw const EngineException(
          'INVALID_DISCARD',
          'Only Double Down allows the target to select a discard',
        );
      }
      if (attackDesign == 'card_02' &&
          target.hand.isNotEmpty &&
          discard == null) {
        throw const EngineException(
          'INVALID_DISCARD',
          'Target must select a card for Double Down if damage succeeds',
        );
      }
      if (discard != null && !target.hand.contains(discard)) {
        throw const EngineException(
          'INVALID_DISCARD',
          'Selected Double Down card must be in target hand',
        );
      }
      final withChoice = state.copyWith(
        pendingAttack: pending.copyWith(targetDiscardCardInstanceId: discard),
      );
      if (pending.stepInPlayerIds.isEmpty) {
        return _resolveDamage(withChoice, nowMs);
      }
      return withChoice.copyWith(
        version: state.version + 1,
        pendingAttack: pending.copyWith(
          targetDiscardCardInstanceId: discard,
          stepInIndex: 0,
        ),
      );
    }
    if (response.discardCardInstanceId != null) {
      throw const EngineException(
        'INVALID_DISCARD',
        'Only the attack target may select a Double Down discard',
      );
    }
    final nextIndex = pending.stepInIndex + 1;
    if (nextIndex >= pending.stepInPlayerIds.length) {
      return _resolveDamage(state, nowMs);
    }
    return state.copyWith(
      version: state.version + 1,
      pendingAttack: pending.copyWith(stepInIndex: nextIndex),
    );
  }
  if (pending.stepInIndex == -1) {
    if (response.kind != AttackResponseKind.defend ||
        response.cardInstanceId == null) {
      throw const EngineException(
        'INVALID_REACTION',
        'Attack target may defend or pass; Step In follows a pass',
      );
    }
    return _resolveDefense(state, responderPlayerId, response.cardInstanceId!);
  }
  if (response.kind != AttackResponseKind.stepIn ||
      response.cardInstanceId == null) {
    throw const EngineException(
      'INVALID_REACTION',
      'Only Step In may be played after the target passes',
    );
  }
  return _resolveStepIn(state, responderPlayerId, response.cardInstanceId!);
}

MatchState playSafePlace(
  MatchState state,
  String casterPlayerId,
  String targetPlayerId,
  String cardInstanceId,
) {
  _requireActiveActor(state, casterPlayerId);
  final target = state.players[targetPlayerId];
  if (target == null ||
      target.status != PlayerStatus.active ||
      target.hearts < 1) {
    throw const EngineException(
      'INVALID_TARGET',
      'Safe Place must target an Active player',
    );
  }
  _requireCard(state, casterPlayerId, cardInstanceId, const {'card_21'});
  if (state.activeEffects.any(
    (effect) => effect.targetPlayerId == targetPlayerId,
  )) {
    throw const EngineException(
      'SAFE_PLACE_ALREADY_ACTIVE',
      'Target already has a Safe Place shield',
    );
  }
  final caster = state.players[casterPlayerId]!;
  final spent = spendAction(state, TurnActionKind.action);
  return spent.copyWith(
    version: state.version + 1,
    players: {
      ...spent.players,
      casterPlayerId: caster.copyWith(
        hand: caster.hand.where((card) => card != cardInstanceId).toList(),
        lastPlayedActionCardInstanceId: cardInstanceId,
      ),
    },
    discardPile: [...state.discardPile, cardInstanceId],
    activeEffects: [
      ...state.activeEffects,
      SafePlaceEffect(
        casterPlayerId: casterPlayerId,
        targetPlayerId: targetPlayerId,
      ),
    ],
  );
}
