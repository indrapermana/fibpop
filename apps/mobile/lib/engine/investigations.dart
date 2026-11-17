import 'deck.dart';
import 'game_state.dart';
import 'random.dart';
import 'suspicion.dart';
import 'turns.dart';

enum EvidenceKind { clue, behavior }

enum InvestigationDefenseKind { discard, misdirection }

class InvestigationDefense {
  const InvestigationDefense({
    required this.kind,
    required this.cardInstanceId,
  });

  final InvestigationDefenseKind kind;
  final String cardInstanceId;
}

class BasicObserveOutcome {
  const BasicObserveOutcome({required this.state, required this.evidenceAdded});

  final MatchState state;
  final bool evidenceAdded;
}

class InvestigationOutcome {
  const InvestigationOutcome({
    required this.state,
    required this.actionCost,
    required this.evidenceAdded,
    required this.inspectedCardInstanceId,
    required this.drawnCardInstanceId,
    required this.revealedActionCardInstanceId,
  });

  final MatchState state;
  final int actionCost;
  final bool evidenceAdded;
  final String? inspectedCardInstanceId;
  final String? drawnCardInstanceId;
  final String? revealedActionCardInstanceId;

  Map<String, Object?> resultToJson() => {
    'actionCost': actionCost,
    'evidenceAdded': evidenceAdded,
    'privateResult': {
      'inspectedCardInstanceId': inspectedCardInstanceId,
      'drawnCardInstanceId': drawnCardInstanceId,
      'revealedActionCardInstanceId': revealedActionCardInstanceId,
    },
  };
}

final _cardInstance = RegExp(r'^(card_\d{2}):[1-9]\d*$');
const _investigationCards = {'card_09', 'card_10', 'card_11', 'card_12'};

String? _cardDesignId(String id) => _cardInstance.firstMatch(id)?.group(1);

void _requireActiveTurnActor(MatchState state, String actorId) {
  if (state.phase != TurnPhase.activeTurn) {
    throw const EngineException(
      'INVALID_PHASE',
      'Investigation requires an active turn',
    );
  }
  if (state.currentPlayerId != actorId) {
    throw const EngineException(
      'NOT_YOUR_TURN',
      'Only the current player may investigate',
    );
  }
  final actor = state.players[actorId];
  if (actor == null ||
      actor.status != PlayerStatus.active ||
      actor.hearts < 1) {
    throw const EngineException(
      'NOT_ELIGIBLE',
      'Investigation requires an Active player',
    );
  }
}

PlayerState _requireTarget(MatchState state, String targetId) {
  final target = state.players[targetId];
  if (target == null) {
    throw EngineException(
      'INVALID_TARGET',
      'Unknown investigation target: $targetId',
    );
  }
  return target;
}

bool _hasEvidence(
  MatchState state,
  String investigatorId,
  String suspectId,
  EvidenceKind kind,
) {
  final evidence = state.players[investigatorId]?.evidence[suspectId];
  return kind == EvidenceKind.clue
      ? evidence?.clue ?? false
      : evidence?.behavior ?? false;
}

MatchState grantEvidence(
  MatchState state,
  String investigatorId,
  String suspectId,
  EvidenceKind kind,
) {
  final investigator = state.players[investigatorId];
  if (investigator == null) {
    throw EngineException(
      'INVALID_PLAYER',
      'Unknown investigator: $investigatorId',
    );
  }
  if (!state.players.containsKey(suspectId)) {
    throw EngineException(
      'INVALID_TARGET',
      'Unknown Evidence target: $suspectId',
    );
  }
  if (_hasEvidence(state, investigatorId, suspectId, kind)) return state;
  final existing = investigator.evidence[suspectId];
  final evidence = Evidence(
    clue: kind == EvidenceKind.clue || (existing?.clue ?? false),
    behavior: kind == EvidenceKind.behavior || (existing?.behavior ?? false),
  );
  return state.copyWith(
    version: state.version + 1,
    players: {
      ...state.players,
      investigatorId: investigator.copyWith(
        evidence: {...investigator.evidence, suspectId: evidence},
      ),
    },
  );
}

BasicObserveOutcome basicObserve(
  MatchState state,
  String actorId,
  String targetId,
) {
  _requireActiveTurnActor(state, actorId);
  _requireTarget(state, targetId);
  final qualifies = hasBehaviorEvidenceQualifyingAction(state, targetId);
  final added =
      qualifies &&
      !_hasEvidence(state, actorId, targetId, EvidenceKind.behavior);
  var next = spendAction(state, TurnActionKind.action);
  if (qualifies) {
    next = grantEvidence(next, actorId, targetId, EvidenceKind.behavior);
  }
  return BasicObserveOutcome(
    state: next.copyWith(version: state.version + 1),
    evidenceAdded: added,
  );
}

InvestigationOutcome playInvestigation(
  MatchState state, {
  required String actorPlayerId,
  required String targetPlayerId,
  required String cardInstanceId,
  required RandomSource random,
  InvestigationDefense? defense,
}) {
  _requireActiveTurnActor(state, actorPlayerId);
  final target = _requireTarget(state, targetPlayerId);
  final actor = state.players[actorPlayerId]!;
  final cardId = _cardDesignId(cardInstanceId);
  if (cardId == null ||
      (!_investigationCards.contains(cardId) && cardId != 'card_22')) {
    throw const EngineException(
      'INVALID_CARD',
      'Unsupported Investigation or Extra Clue',
    );
  }
  if (!actor.hand.contains(cardInstanceId)) {
    throw const EngineException(
      'INVALID_CARD',
      'Investigation card must be in the current player hand',
    );
  }
  if (cardId == 'card_11' && targetPlayerId == actorPlayerId) {
    throw const EngineException(
      'INVALID_TARGET',
      'Peek must target another player',
    );
  }
  final inspectsHand =
      cardId == 'card_10' || cardId == 'card_11' || cardId == 'card_22';
  if (defense != null && !inspectsHand) {
    throw const EngineException(
      'INVALID_INSPECTION_DEFENSE',
      'This Investigation does not inspect a hand',
    );
  }
  final targetHand = targetPlayerId == actorPlayerId
      ? target.hand.where((card) => card != cardInstanceId).toList()
      : target.hand;
  if (defense != null) {
    if (!targetHand.contains(defense.cardInstanceId)) {
      throw const EngineException(
        'INVALID_INSPECTION_DEFENSE',
        'Defense card must be in the target hand',
      );
    }
    if (defense.kind == InvestigationDefenseKind.misdirection &&
        (targetPlayerId == actorPlayerId ||
            _cardDesignId(defense.cardInstanceId) != 'card_24')) {
      throw const EngineException(
        'INVALID_INSPECTION_DEFENSE',
        'Misdirection must be played by the other target',
      );
    }
    if (defense.kind == InvestigationDefenseKind.discard &&
        cardId != 'card_22') {
      throw const EngineException(
        'INVALID_INSPECTION_DEFENSE',
        'Only Extra Clue permits a discard defense',
      );
    }
  }

  final isInvestigation = _investigationCards.contains(cardId);
  final first =
      isInvestigation &&
      !state.investigationTargetsThisTurn.contains(targetPlayerId);
  final cost = first && target.suspicion == 3 ? 0 : 1;
  final spent = spendAction(state, TurnActionKind.action, cost: cost);
  final players = {...spent.players};
  players[actorPlayerId] = actor.copyWith(
    hand: actor.hand.where((card) => card != cardInstanceId).toList(),
    lastPlayedActionCardInstanceId: cardInstanceId,
  );
  if (defense != null) {
    final defender = players[targetPlayerId]!;
    players[targetPlayerId] = defender.copyWith(
      hand: defender.hand
          .where((card) => card != defense.cardInstanceId)
          .toList(),
    );
  }
  var discardPile = [
    ...spent.discardPile,
    cardInstanceId,
    if (defense != null) defense.cardInstanceId,
  ];
  final investigationTargets = isInvestigation && first
      ? [...state.investigationTargetsThisTurn, targetPlayerId]
      : state.investigationTargetsThisTurn;
  String? inspected;
  if (inspectsHand && defense == null && targetHand.isNotEmpty) {
    inspected = targetHand[randomIndex(targetHand.length, random)];
  }
  String? drawn;
  var drawPile = [...spent.drawPile];
  if (cardId == 'card_11') {
    final draw = drawCardsFromPiles(drawPile, discardPile, 1, random);
    drawn = draw.cards.isEmpty ? null : draw.cards.single;
    drawPile = draw.drawPile;
    discardPile = draw.discardPile;
    if (drawn != null) {
      final currentActor = players[actorPlayerId]!;
      players[actorPlayerId] = currentActor.copyWith(
        hand: [...currentActor.hand, drawn],
      );
    }
  }
  EvidenceKind? evidenceKind;
  if (cardId == 'card_10' || cardId == 'card_12' || cardId == 'card_22') {
    evidenceKind = EvidenceKind.clue;
  } else if (cardId == 'card_09' &&
      hasBehaviorEvidenceQualifyingAction(state, targetPlayerId)) {
    evidenceKind = EvidenceKind.behavior;
  }
  final evidenceAdded =
      evidenceKind != null &&
      !_hasEvidence(state, actorPlayerId, targetPlayerId, evidenceKind);
  var next = spent.copyWith(
    version: state.version + 1,
    players: players,
    drawPile: drawPile,
    discardPile: discardPile,
    investigationTargetsThisTurn: investigationTargets,
  );
  if (evidenceKind != null) {
    next = grantEvidence(next, actorPlayerId, targetPlayerId, evidenceKind);
  }
  return InvestigationOutcome(
    state: next.copyWith(version: state.version + 1),
    actionCost: cost,
    evidenceAdded: evidenceAdded,
    inspectedCardInstanceId: inspected,
    drawnCardInstanceId: drawn,
    revealedActionCardInstanceId: cardId == 'card_12'
        ? players[targetPlayerId]!.lastPlayedActionCardInstanceId
        : null,
  );
}
