import 'deck.dart';
import 'game_state.dart';
import 'random.dart';
import 'suspicion.dart';
import 'turns.dart';

const _pointFingersCards = {'card_13'};
const _cleanSlateCards = {'card_14'};
const _stirThePotCards = {'card_15'};
const _cardSwapCards = {'card_16'};
const _firstAidCards = {'card_17'};
const _catchYourBreathCards = {'card_18'};
const _patchUpCards = {'card_20'};
const _spotlightCards = {'card_23'};
final _cardInstance = RegExp(r'^(card_\d{2}):[1-9]\d*$');

String? _cardDesignId(String id) => _cardInstance.firstMatch(id)?.group(1);

MatchState _playActionCard(
  MatchState state,
  String actorPlayerId,
  String cardInstanceId,
  Set<String> allowedCardDesignIds,
) {
  if (state.phase != TurnPhase.activeTurn) {
    throw const EngineException(
      'INVALID_PHASE',
      'An Action card can only be played during the active turn',
    );
  }
  if (state.currentPlayerId != actorPlayerId) {
    throw const EngineException(
      'NOT_YOUR_TURN',
      'Only the current player may play an Action card',
    );
  }
  final actor = state.players[actorPlayerId];
  if (actor == null ||
      actor.status != PlayerStatus.active ||
      actor.hearts < 1) {
    throw const EngineException(
      'NOT_ELIGIBLE',
      'An Action card requires an Active player',
    );
  }
  final designId = _cardDesignId(cardInstanceId);
  if (designId == null ||
      !allowedCardDesignIds.contains(designId) ||
      !actor.hand.contains(cardInstanceId)) {
    throw const EngineException(
      'INVALID_CARD',
      'The selected Action card must be in the player hand',
    );
  }

  final spent = spendAction(state, TurnActionKind.action);
  return spent.copyWith(
    players: {
      ...spent.players,
      actorPlayerId: actor.copyWith(
        hand: actor.hand.where((card) => card != cardInstanceId).toList(),
        lastPlayedActionCardInstanceId: cardInstanceId,
      ),
    },
    discardPile: [...state.discardPile, cardInstanceId],
  );
}

void _requireSurvivingTarget(
  MatchState state,
  String actorPlayerId,
  String targetPlayerId,
) {
  final target = state.players[targetPlayerId];
  if (target == null ||
      targetPlayerId == actorPlayerId ||
      target.status == PlayerStatus.eliminated) {
    throw const EngineException(
      'INVALID_TARGET',
      'The selected target must be another surviving player',
    );
  }
}

MatchState _finishNoisyManipulation(MatchState state, String actorPlayerId) =>
    recordNoisyManipulation(
      state,
      actorPlayerId,
    ).copyWith(version: state.version);

MatchState playPointFingers(
  MatchState state,
  String actorPlayerId,
  String targetPlayerId,
  String cardInstanceId,
) {
  _requireSurvivingTarget(state, actorPlayerId, targetPlayerId);
  final played = _playActionCard(
    state,
    actorPlayerId,
    cardInstanceId,
    _pointFingersCards,
  );
  final target = played.players[targetPlayerId]!;
  final targeted = played.copyWith(
    players: {
      ...played.players,
      targetPlayerId: target.copyWith(
        suspicion: (target.suspicion + 1).clamp(0, maxSuspicion).toInt(),
      ),
    },
  );
  return _finishNoisyManipulation(targeted, actorPlayerId);
}

MatchState playCleanSlate(
  MatchState state,
  String actorPlayerId,
  String cardInstanceId,
) {
  final played = _playActionCard(
    state,
    actorPlayerId,
    cardInstanceId,
    _cleanSlateCards,
  );
  final actor = played.players[actorPlayerId]!;
  final reduced = played.copyWith(
    players: {
      ...played.players,
      actorPlayerId: actor.copyWith(
        suspicion: (actor.suspicion - 2).clamp(0, maxSuspicion).toInt(),
      ),
    },
  );
  return _finishNoisyManipulation(reduced, actorPlayerId);
}

MatchState playStirThePot(
  MatchState state,
  String actorPlayerId,
  List<String> targetPlayerIds,
  String cardInstanceId,
) {
  if (targetPlayerIds.length != 2 ||
      targetPlayerIds.toSet().length != 2 ||
      targetPlayerIds.any((id) {
        final target = state.players[id];
        return target == null ||
            id == actorPlayerId ||
            target.status != PlayerStatus.active ||
            target.hearts < 1 ||
            target.hand.isEmpty;
      })) {
    throw const EngineException(
      'INVALID_TARGET',
      'Stir the Pot requires two different other Active players with cards',
    );
  }
  final actorIndex = state.seatOrder.indexOf(actorPlayerId);
  if (actorIndex < 0) {
    throw const EngineException(
      'INVALID_PLAYER',
      'The current player must have a seat to play Stir the Pot',
    );
  }
  int clockwiseDistance(String playerId) =>
      (state.seatOrder.indexOf(playerId) -
          actorIndex +
          state.seatOrder.length) %
      state.seatOrder.length;
  final orderedTargets = [...targetPlayerIds]
    ..sort(
      (left, right) =>
          clockwiseDistance(left).compareTo(clockwiseDistance(right)),
    );
  final played = _playActionCard(
    state,
    actorPlayerId,
    cardInstanceId,
    _stirThePotCards,
  );
  final noisy = _finishNoisyManipulation(played, actorPlayerId);
  return noisy.copyWith(
    phase: TurnPhase.awaitingCardEffect,
    pendingCardEffect: PendingCardEffect.stirThePot(
      actorPlayerId,
      orderedTargets,
      0,
    ),
  );
}

String? currentCardEffectResponder(MatchState state) {
  if (state.phase != TurnPhase.awaitingCardEffect ||
      state.pendingCardEffect == null) {
    return null;
  }
  final pending = state.pendingCardEffect!;
  if (pending.kind == 'catch_your_breath_discard') {
    return pending.actorPlayerId;
  }
  if (pending.kind == 'stir_the_pot_discards') {
    return pending.responseIndex < pending.targetPlayerIds.length
        ? pending.targetPlayerIds[pending.responseIndex]
        : null;
  }
  return null;
}

class CardEffectDiscardOutcome {
  const CardEffectDiscardOutcome({
    required this.state,
    required this.nextResponderPlayerId,
  });

  final MatchState state;
  final String? nextResponderPlayerId;
}

CardEffectDiscardOutcome respondToCardEffectDiscard(
  MatchState state,
  String responderPlayerId,
  String cardInstanceId,
) {
  final pending = state.pendingCardEffect;
  if (state.phase != TurnPhase.awaitingCardEffect || pending == null) {
    throw const EngineException(
      'INVALID_PHASE',
      'A card-effect discard requires a pending card effect',
    );
  }
  if (currentCardEffectResponder(state) != responderPlayerId) {
    throw const EngineException(
      'NOT_YOUR_TURN',
      'Only the current card-effect responder may discard',
    );
  }
  final responder = state.players[responderPlayerId];
  if (responder == null || !responder.hand.contains(cardInstanceId)) {
    throw const EngineException(
      'INVALID_DISCARD',
      'The selected card must be in the responder hand',
    );
  }
  final players = {
    ...state.players,
    responderPlayerId: responder.copyWith(
      hand: responder.hand.where((card) => card != cardInstanceId).toList(),
    ),
  };
  final discardPile = [...state.discardPile, cardInstanceId];
  if (pending.kind == 'catch_your_breath_discard' ||
      pending.responseIndex == 1) {
    final completed = state.copyWith(
      version: state.version + 1,
      phase: TurnPhase.activeTurn,
      clearPendingCardEffect: true,
      players: players,
      discardPile: discardPile,
    );
    return CardEffectDiscardOutcome(
      state: completed,
      nextResponderPlayerId: null,
    );
  }
  final next = state.copyWith(
    version: state.version + 1,
    pendingCardEffect: pending.copyWith(responseIndex: 1),
    players: players,
    discardPile: discardPile,
  );
  return CardEffectDiscardOutcome(
    state: next,
    nextResponderPlayerId: currentCardEffectResponder(next),
  );
}

class CardSwapOutcome {
  const CardSwapOutcome({
    required this.state,
    required this.givenToTargetCardInstanceId,
    required this.receivedCardInstanceId,
  });

  final MatchState state;
  final String givenToTargetCardInstanceId;
  final String receivedCardInstanceId;
}

CardSwapOutcome playCardSwap(
  MatchState state,
  String actorPlayerId,
  String targetPlayerId,
  String cardInstanceId,
  RandomSource random,
) {
  _requireSurvivingTarget(state, actorPlayerId, targetPlayerId);
  if (state.players[targetPlayerId]!.hand.isEmpty) {
    throw const EngineException(
      'INVALID_TARGET',
      'Card Swap requires the target to have a card',
    );
  }
  final played = _playActionCard(
    state,
    actorPlayerId,
    cardInstanceId,
    _cardSwapCards,
  );
  final actor = played.players[actorPlayerId]!;
  if (actor.hand.isEmpty) {
    throw const EngineException(
      'INVALID_CARD',
      'Card Swap requires the current player to have another card',
    );
  }
  final target = played.players[targetPlayerId]!;
  final givenCard = actor.hand[randomIndex(actor.hand.length, random)];
  final receivedCard = target.hand[randomIndex(target.hand.length, random)];
  final swapped = played.copyWith(
    players: {
      ...played.players,
      actorPlayerId: actor.copyWith(
        hand: [...actor.hand.where((card) => card != givenCard), receivedCard],
      ),
      targetPlayerId: target.copyWith(
        hand: [...target.hand.where((card) => card != receivedCard), givenCard],
      ),
    },
  );
  return CardSwapOutcome(
    state: swapped,
    givenToTargetCardInstanceId: givenCard,
    receivedCardInstanceId: receivedCard,
  );
}

MatchState playFirstAid(
  MatchState state,
  String actorPlayerId,
  String targetPlayerId,
  String cardInstanceId,
) {
  final target = state.players[targetPlayerId];
  if (target == null || target.status == PlayerStatus.eliminated) {
    throw const EngineException(
      'INVALID_TARGET',
      'First Aid must target a surviving player',
    );
  }
  final played = _playActionCard(
    state,
    actorPlayerId,
    cardInstanceId,
    _firstAidCards,
  );
  final healedTarget = played.players[targetPlayerId]!;
  return played.copyWith(
    players: {
      ...played.players,
      targetPlayerId: healedTarget.copyWith(
        hearts: (healedTarget.hearts + 1).clamp(0, 3).toInt(),
        status: healedTarget.status == PlayerStatus.cornered
            ? PlayerStatus.active
            : healedTarget.status,
      ),
    },
  );
}

class CatchYourBreathOutcome {
  const CatchYourBreathOutcome({
    required this.state,
    required this.drawnCardInstanceIds,
  });

  final MatchState state;
  final List<String> drawnCardInstanceIds;
}

CatchYourBreathOutcome playCatchYourBreath(
  MatchState state,
  String actorPlayerId,
  String cardInstanceId,
  RandomSource random,
) {
  final played = _playActionCard(
    state,
    actorPlayerId,
    cardInstanceId,
    _catchYourBreathCards,
  );
  final draw = drawCardsFromPiles(
    played.drawPile,
    played.discardPile,
    2,
    random,
  );
  final actor = played.players[actorPlayerId]!;
  final next = played.copyWith(
    phase: TurnPhase.awaitingCardEffect,
    pendingCardEffect: PendingCardEffect.catchYourBreath(actorPlayerId),
    players: {
      ...played.players,
      actorPlayerId: actor.copyWith(hand: [...actor.hand, ...draw.cards]),
    },
    drawPile: draw.drawPile,
    discardPile: draw.discardPile,
  );
  return CatchYourBreathOutcome(state: next, drawnCardInstanceIds: draw.cards);
}

MatchState playPatchUp(
  MatchState state,
  String actorPlayerId,
  String cardInstanceId,
) {
  final played = _playActionCard(
    state,
    actorPlayerId,
    cardInstanceId,
    _patchUpCards,
  );
  final actor = played.players[actorPlayerId]!;
  return played.copyWith(
    players: {
      ...played.players,
      actorPlayerId: actor.copyWith(
        hearts: (actor.hearts + 1).clamp(0, 3).toInt(),
        suspicion: (actor.suspicion - 1).clamp(0, maxSuspicion).toInt(),
      ),
    },
  );
}

class SpotlightOutcome {
  const SpotlightOutcome({
    required this.state,
    required this.suspicionByPlayerId,
    required this.drawnCardInstanceId,
  });

  final MatchState state;
  final Map<String, int> suspicionByPlayerId;
  final String? drawnCardInstanceId;
}

SpotlightOutcome playSpotlight(
  MatchState state,
  String actorPlayerId,
  String cardInstanceId,
  RandomSource random,
) {
  final played = _playActionCard(
    state,
    actorPlayerId,
    cardInstanceId,
    _spotlightCards,
  );
  final draw = drawCardsFromPiles(
    played.drawPile,
    played.discardPile,
    1,
    random,
  );
  final actor = played.players[actorPlayerId]!;
  return SpotlightOutcome(
    state: played.copyWith(
      players: {
        ...played.players,
        actorPlayerId: actor.copyWith(hand: [...actor.hand, ...draw.cards]),
      },
      drawPile: draw.drawPile,
      discardPile: draw.discardPile,
    ),
    suspicionByPlayerId: {
      for (final entry in played.players.entries)
        entry.key: entry.value.suspicion,
    },
    drawnCardInstanceId: draw.cards.isEmpty ? null : draw.cards.first,
  );
}
