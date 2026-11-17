import 'attacks.dart';
import 'cornered.dart';
import 'game_state.dart';
import 'outcomes.dart';
import 'turns.dart';

sealed class PlayerDeparture {
  const PlayerDeparture();
}

class DisconnectDeparture extends PlayerDeparture {
  const DisconnectDeparture();
}

class ForfeitDeparture extends PlayerDeparture {
  const ForfeitDeparture(this.nowMs);

  final int nowMs;
}

MatchState handlePlayerDeparture(
  MatchState state,
  String playerId,
  PlayerDeparture departure,
) {
  final player = state.players[playerId];
  if (player == null || !state.seatOrder.contains(playerId)) {
    throw const EngineException(
      'INVALID_PLAYER',
      'The player must belong to the match',
    );
  }
  if (departure is DisconnectDeparture) return state;
  if (departure is! ForfeitDeparture) {
    throw const EngineException('INVALID_COMMAND', 'Invalid player departure');
  }

  final nowMs = departure.nowMs;
  const maxSafeInteger = 9007199254740991;
  const maxDateMillis = 8640000000000000;
  if (nowMs < 0 || nowMs > maxSafeInteger || nowMs > maxDateMillis) {
    throw const EngineException(
      'INVALID_DEADLINE',
      'A valid timestamp is required',
    );
  }
  if (state.phase == TurnPhase.finished || state.phase == TurnPhase.cancelled) {
    throw const EngineException(
      'INVALID_PHASE',
      'A forfeit requires an ongoing match',
    );
  }
  if (player.status == PlayerStatus.eliminated || player.role == null) {
    throw const EngineException('NOT_ELIGIBLE', 'The player cannot forfeit');
  }

  final deadlineUtc = state.deadlineUtc;
  if (deadlineUtc != null) {
    final deadline = DateTime.tryParse(deadlineUtc)?.millisecondsSinceEpoch;
    if (deadline == null) {
      throw const EngineException(
        'INVALID_DEADLINE',
        'A valid timestamp is required',
      );
    }
    if (nowMs >= deadline) {
      throw const EngineException(
        'WINDOW_EXPIRED',
        'Resolve the expired window before the forfeit',
      );
    }
    final duration = switch (state.phase) {
      TurnPhase.awaitingAccusation => accusationOfferMs,
      TurnPhase.awaitingSecretFinish => secretFinishWindowMs,
      _ => lastChanceWindowMs,
    };
    if (nowMs < deadline - duration) {
      throw const EngineException(
        'INVALID_DEADLINE',
        'The timestamp precedes the response window',
      );
    }
  }

  final updated = state.copyWith(
    version: state.version + 1,
    players: {
      ...state.players,
      playerId: player.copyWith(status: PlayerStatus.eliminated),
    },
  );
  if (player.role == PlayerRole.impostor) {
    return updated.copyWith(
      phase: TurnPhase.cancelled,
      clearCurrentPlayerId: true,
      clearDeadlineUtc: true,
      clearPendingAttack: true,
      clearPendingCornered: true,
      clearPendingSecretFinish: true,
      winner: const MatchOutcome.cancelled(),
    );
  }

  final winner = findImpostorWinner(updated);
  if (winner != null) return winner;

  var result = updated;
  if (state.phase == TurnPhase.turnStart ||
      state.phase == TurnPhase.activeTurn) {
    if (state.currentPlayerId == playerId) {
      result = advanceTurnAfterElimination(
        updated.copyWith(phase: TurnPhase.activeTurn),
      );
    }
  } else if (state.phase == TurnPhase.awaitingReaction) {
    final pending = state.pendingAttack;
    if (pending == null) {
      throw const EngineException(
        'INVALID_PHASE',
        'A pending attack is required',
      );
    }
    if (pending.attackerPlayerId == playerId ||
        pending.targetPlayerId == playerId) {
      result = resumeInterruptedTurn(updated);
    } else {
      final currentResponder = currentAttackResponder(state);
      final remainingResponders = [
        for (var index = 0; index < pending.stepInPlayerIds.length; index++)
          if (pending.stepInPlayerIds[index] != playerId ||
              index <= pending.stepInIndex)
            pending.stepInPlayerIds[index],
      ];
      result = updated.copyWith(
        pendingAttack: pending.copyWith(stepInPlayerIds: remainingResponders),
      );
      if (currentResponder == playerId) {
        result = respondToAttack(
          result,
          playerId,
          const AttackResponse.pass(),
          nowMs: nowMs,
        );
      }
    }
  } else if (state.phase == TurnPhase.awaitingAccusation) {
    final pending = state.pendingCornered;
    if (pending == null) {
      throw const EngineException(
        'INVALID_PHASE',
        'A pending Cornered target is required',
      );
    }
    if (pending.targetPlayerId == playerId) {
      result = resumeInterruptedTurn(updated);
    } else {
      final currentAccuser = currentAccusationPlayerId(state);
      final remainingAccusers = [
        for (
          var index = 0;
          index < pending.accusationOrderPlayerIds.length;
          index++
        )
          if (pending.accusationOrderPlayerIds[index] != playerId ||
              index <= pending.accusationIndex)
            pending.accusationOrderPlayerIds[index],
      ];
      result = updated.copyWith(
        pendingCornered: pending.copyWith(
          accusationOrderPlayerIds: remainingAccusers,
        ),
      );
      if (currentAccuser == playerId && !pending.accusationPassed) {
        result = respondToAccusation(
          result,
          playerId,
          const AccusationResponse.pass(),
          nowMs,
        );
      }
    }
  } else if (state.phase == TurnPhase.awaitingCardEffect) {
    final pending = state.pendingCardEffect;
    if (pending == null) {
      throw const EngineException(
        'INVALID_PHASE',
        'A pending card effect is required',
      );
    }
    if (pending.actorPlayerId == playerId ||
        (pending.kind == 'stir_the_pot_discards' &&
            pending.targetPlayerIds.contains(playerId))) {
      result = resumeInterruptedTurn(updated);
    }
  } else if (state.phase == TurnPhase.awaitingSecretFinish ||
      state.phase == TurnPhase.awaitingLastChance) {
    final pending = state.pendingCornered;
    if (pending == null) {
      throw const EngineException(
        'INVALID_PHASE',
        'A pending Cornered target is required',
      );
    }
    if (pending.targetPlayerId == playerId) {
      result = resumeInterruptedTurn(updated);
    } else if (state.phase == TurnPhase.awaitingSecretFinish) {
      final secretFinish = state.pendingSecretFinish;
      if (secretFinish == null) {
        throw const EngineException(
          'INVALID_PHASE',
          'A pending Secret Finish window is required',
        );
      }
      final submissions = {...secretFinish.submissions}..remove(playerId);
      result = updated.copyWith(
        pendingSecretFinish: PendingSecretFinish(
          targetPlayerId: secretFinish.targetPlayerId,
          eligiblePlayerIds: secretFinish.eligiblePlayerIds
              .where((id) => id != playerId)
              .toList(),
          submissions: submissions,
        ),
      );
    }
  }

  return result.copyWith(version: state.version + 1);
}
