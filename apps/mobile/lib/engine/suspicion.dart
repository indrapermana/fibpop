import 'game_state.dart';
import 'turns.dart';

const maxSuspicion = 3;

MatchState adjustSuspicion(MatchState state, String playerId, num change) {
  if (!change.isFinite || change.truncateToDouble() != change) {
    throw const EngineException(
      'INVALID_SUSPICION_CHANGE',
      'Suspicion change must be an integer',
    );
  }
  final player = state.players[playerId];
  if (player == null) {
    throw EngineException('INVALID_PLAYER', 'Unknown player: $playerId');
  }
  final suspicion = (player.suspicion + change.toInt())
      .clamp(0, maxSuspicion)
      .toInt();
  return state.copyWith(
    version: state.version + 1,
    players: {
      ...state.players,
      playerId: player.copyWith(suspicion: suspicion),
    },
  );
}

MatchState recordNoisyManipulation(MatchState state, String actorPlayerId) {
  if (state.phase != TurnPhase.activeTurn) {
    throw const EngineException(
      'INVALID_ACTION_PHASE',
      'A noisy manipulation can only be recorded during the active turn',
    );
  }
  if (state.currentPlayerId != actorPlayerId) {
    throw const EngineException(
      'NOT_YOUR_TURN',
      'Only the current player may perform a noisy manipulation',
    );
  }
  final actor = state.players[actorPlayerId];
  if (actor == null ||
      actor.status != PlayerStatus.active ||
      actor.hearts < 1) {
    throw const EngineException(
      'NOT_ELIGIBLE',
      'A noisy manipulation requires an Active player',
    );
  }
  return state.copyWith(
    version: state.version + 1,
    players: {
      ...state.players,
      actorPlayerId: actor.copyWith(
        suspicion: (actor.suspicion + 1).clamp(0, maxSuspicion).toInt(),
      ),
    },
    publicActionHistory: [
      ...state.publicActionHistory,
      PublicAction(playerId: actorPlayerId, kind: 'noisy_manipulation'),
    ],
  );
}

MatchState recordSuccessfulAttackDamage(
  MatchState state,
  String attackerPlayerId,
) {
  if (state.phase != TurnPhase.activeTurn &&
      state.phase != TurnPhase.awaitingAccusation) {
    throw const EngineException(
      'INVALID_ACTION_PHASE',
      'Successful attack damage is invalid in the current phase',
    );
  }
  if (state.currentPlayerId != attackerPlayerId ||
      state.attacksUsedThisTurn != 1) {
    throw const EngineException(
      'INVALID_ACTION_PHASE',
      "Successful attack damage must follow the current player's attack",
    );
  }
  final attacker = state.players[attackerPlayerId];
  if (attacker == null ||
      attacker.status != PlayerStatus.active ||
      attacker.hearts < 1) {
    throw const EngineException(
      'NOT_ELIGIBLE',
      'Successful attack damage requires an Active attacker',
    );
  }
  if (state.suspicionAwardedForDamageThisTurn) {
    throw const EngineException(
      'DUPLICATE_ATTACK_RECORD',
      'Successful attack damage was already recorded this turn',
    );
  }
  return state.copyWith(
    version: state.version + 1,
    suspicionAwardedForDamageThisTurn: true,
    players: {
      ...state.players,
      attackerPlayerId: attacker.copyWith(
        suspicion: (attacker.suspicion + 1).clamp(0, maxSuspicion).toInt(),
      ),
    },
    publicActionHistory: [
      ...state.publicActionHistory,
      PublicAction(playerId: attackerPlayerId, kind: 'successful_attack'),
    ],
  );
}

bool hasBehaviorEvidenceQualifyingAction(MatchState state, String playerId) =>
    state.publicActionHistory.any(
      (action) =>
          action.playerId == playerId &&
          (action.kind == 'successful_attack' ||
              action.kind == 'noisy_manipulation'),
    );
