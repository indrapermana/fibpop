import 'deck.dart';
import 'game_state.dart';
import 'random.dart';

class EngineException implements Exception {
  const EngineException(this.code, this.message);
  final String code;
  final String message;

  @override
  String toString() => '$code: $message';
}

enum TurnActionKind { attack, action }

MatchState beginTurn(MatchState state, RandomSource random) {
  if (state.phase != TurnPhase.turnStart) {
    throw StateError(
      'A turn can begin drawing only during the turn_start phase',
    );
  }
  final playerId = state.currentPlayerId;
  final player = state.players[playerId];
  if (playerId == null ||
      player == null ||
      player.status != PlayerStatus.active) {
    throw StateError('The current player must be Active to draw at turn start');
  }
  final draw = drawCardsFromPiles(state.drawPile, state.discardPile, 2, random);
  return state.copyWith(
    phase: TurnPhase.activeTurn,
    version: state.version + 1,
    actionsRemaining: 2,
    attacksUsedThisTurn: 0,
    suspicionAwardedForDamageThisTurn: false,
    investigationTargetsThisTurn: [],
    players: {
      ...state.players,
      playerId: player.copyWith(hand: [...player.hand, ...draw.cards]),
    },
    drawPile: draw.drawPile,
    discardPile: draw.discardPile,
  );
}

MatchState spendAction(MatchState state, TurnActionKind kind, {int cost = 1}) {
  if (state.phase != TurnPhase.activeTurn) {
    throw const EngineException(
      'INVALID_PHASE',
      'An action requires an active turn',
    );
  }
  if (cost != 0 && cost != 1 || kind == TurnActionKind.attack && cost != 1) {
    throw const EngineException('INVALID_ACTION_COST', 'Invalid action cost');
  }
  if (kind == TurnActionKind.attack && state.attacksUsedThisTurn >= 1) {
    throw const EngineException(
      'ATTACK_LIMIT',
      'Only one attack is allowed per turn',
    );
  }
  if (cost == 1 && state.actionsRemaining < 1) {
    throw const EngineException(
      'NO_ACTIONS_REMAIN',
      'No actions remain this turn',
    );
  }
  return state.copyWith(
    version: state.version + 1,
    actionsRemaining: state.actionsRemaining - cost,
    attacksUsedThisTurn:
        state.attacksUsedThisTurn + (kind == TurnActionKind.attack ? 1 : 0),
  );
}

MatchState endTurn(MatchState state, List<String> discards) {
  if (state.phase != TurnPhase.activeTurn) {
    throw const EngineException(
      'INVALID_PHASE',
      'A turn can end only during an active turn',
    );
  }

  final currentId = state.currentPlayerId;
  final seatIndex = state.seatOrder.indexOf(currentId ?? '');
  final current = state.players[currentId];
  if (currentId == null ||
      seatIndex < 0 ||
      current == null ||
      current.status != PlayerStatus.active) {
    throw StateError('The active turn must belong to an Active seated player');
  }
  final requiredCount = (current.hand.length - 7).clamp(0, current.hand.length);
  if (discards.length != requiredCount) {
    throw EngineException(
      'INVALID_DISCARD_COUNT',
      'Discard exactly $requiredCount cards',
    );
  }
  if (discards.toSet().length != discards.length ||
      discards.any((card) => !current.hand.contains(card))) {
    throw const EngineException(
      'INVALID_DISCARD',
      'Discarded cards must be unique and in hand',
    );
  }
  final discarded = discards.toSet();
  final players = {
    ...state.players,
    currentId: current.copyWith(
      hand: current.hand.where((card) => !discarded.contains(card)).toList(),
    ),
  };
  var effects = [...state.activeEffects];
  String? next;
  for (var offset = 1; offset <= state.seatOrder.length; offset++) {
    final id = state.seatOrder[(seatIndex + offset) % state.seatOrder.length];
    final player = players[id];
    if (player == null) throw StateError('Missing player state for seat $id');
    if (player.status == PlayerStatus.eliminated) continue;
    effects = effects.where((effect) => effect.casterPlayerId != id).toList();
    if (player.status == PlayerStatus.cornered) {
      if (player.hearts != 0) {
        throw StateError('Cornered player $id must have 0 Hearts');
      }
      players[id] = player.copyWith(status: PlayerStatus.active, hearts: 1);
      continue;
    }
    if (player.hearts < 1) {
      throw StateError('Active player $id must have at least 1 Heart');
    }
    next = id;
    break;
  }
  if (next == null) {
    throw StateError('No eligible player found to take the next turn');
  }
  return state.copyWith(
    phase: TurnPhase.turnStart,
    version: state.version + 1,
    actionsRemaining: 0,
    attacksUsedThisTurn: 0,
    suspicionAwardedForDamageThisTurn: false,
    investigationTargetsThisTurn: [],
    currentPlayerId: next,
    players: players,
    discardPile: [...state.discardPile, ...discards],
    activeEffects: effects,
  );
}

MatchState advanceTurnAfterElimination(MatchState state) {
  if (state.phase != TurnPhase.activeTurn) {
    throw const EngineException(
      'INVALID_PHASE',
      'An eliminated turn owner can only be advanced from active_turn',
    );
  }
  final currentPlayerId = state.currentPlayerId;
  final currentSeatIndex = state.seatOrder.indexOf(currentPlayerId ?? '');
  if (currentPlayerId == null || currentSeatIndex < 0) {
    throw const EngineException(
      'INVALID_PLAYER',
      'The eliminated turn owner must have a seat',
    );
  }
  if (state.players[currentPlayerId]?.status != PlayerStatus.eliminated) {
    throw const EngineException(
      'NOT_ELIGIBLE',
      'The current turn owner must be eliminated before advancing',
    );
  }

  final players = {...state.players};
  var effects = state.activeEffects
      .where((effect) => effect.casterPlayerId != currentPlayerId)
      .toList();
  String? next;
  String? recovered;
  for (var offset = 1; offset <= state.seatOrder.length; offset++) {
    final id =
        state.seatOrder[(currentSeatIndex + offset) % state.seatOrder.length];
    final player = players[id];
    if (player == null) throw StateError('Missing player state for seat $id');
    if (player.status == PlayerStatus.eliminated) continue;
    effects = effects.where((effect) => effect.casterPlayerId != id).toList();
    if (player.status == PlayerStatus.cornered) {
      if (player.hearts != 0) {
        throw StateError('Cornered player $id must have 0 Hearts');
      }
      players[id] = player.copyWith(status: PlayerStatus.active, hearts: 1);
      recovered ??= id;
      continue;
    }
    if (player.hearts < 1) {
      throw StateError('Active player $id must have at least 1 Heart');
    }
    next = id;
    break;
  }
  next ??= recovered;
  if (next == null) {
    throw const EngineException(
      'NO_ELIGIBLE_PLAYER',
      'No surviving player can take the next turn',
    );
  }
  return state.copyWith(
    phase: TurnPhase.turnStart,
    version: state.version + 1,
    actionsRemaining: 0,
    attacksUsedThisTurn: 0,
    suspicionAwardedForDamageThisTurn: false,
    investigationTargetsThisTurn: [],
    currentPlayerId: next,
    players: players,
    activeEffects: effects,
    clearDeadlineUtc: true,
    clearPendingAttack: true,
    clearPendingCardEffect: true,
    clearPendingCornered: true,
    clearPendingSecretFinish: true,
  );
}
