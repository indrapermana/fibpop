import 'game_state.dart';
import 'outcomes.dart';
import 'turns.dart';

const accusationOfferMs = 10000;
const secretFinishWindowMs = 10000;
const lastChanceWindowMs = 10000;
final _cardInstance = RegExp(r'^(card_\d{2}):[1-9]\d*$');

enum AccusationResponseKind { pass, accuse }

class AccusationResponse {
  const AccusationResponse.pass() : kind = AccusationResponseKind.pass;
  const AccusationResponse.accuse() : kind = AccusationResponseKind.accuse;

  final AccusationResponseKind kind;
}

String? _cardDesignId(String id) => _cardInstance.firstMatch(id)?.group(1);

String _deadlineFromNow(int nowMs, int durationMs) {
  const maxSafeInteger = 9007199254740991;
  const maxDateMillis = 8640000000000000;
  if (nowMs < 0 ||
      nowMs > maxSafeInteger ||
      nowMs > maxDateMillis - durationMs) {
    throw const EngineException(
      'INVALID_DEADLINE',
      'A finite epoch-millisecond timestamp is required',
    );
  }
  return DateTime.fromMillisecondsSinceEpoch(
    nowMs + durationMs,
    isUtc: true,
  ).toIso8601String();
}

int _deadlineMillis(MatchState state, int nowMs) {
  const maxSafeInteger = 9007199254740991;
  if (nowMs < 0 || nowMs > maxSafeInteger || state.deadlineUtc == null) {
    throw const EngineException(
      'INVALID_DEADLINE',
      'A timestamp and active window deadline are required',
    );
  }
  final deadline = DateTime.tryParse(state.deadlineUtc!);
  if (deadline == null) {
    throw const EngineException(
      'INVALID_DEADLINE',
      'A timestamp and active window deadline are required',
    );
  }
  return deadline.millisecondsSinceEpoch;
}

void _requireWindowOpen(MatchState state, int nowMs) {
  final deadline = _deadlineMillis(state, nowMs);
  if (nowMs >= deadline) {
    throw const EngineException(
      'WINDOW_EXPIRED',
      'The response window has expired',
    );
  }
  if (nowMs < deadline - 10000) {
    throw const EngineException(
      'INVALID_DEADLINE',
      'The timestamp precedes the response window',
    );
  }
}

void _requireWindowExpired(MatchState state, int nowMs) {
  if (nowMs < 0 || nowMs < _deadlineMillis(state, nowMs)) {
    throw const EngineException(
      'WINDOW_NOT_EXPIRED',
      'The response window has not expired',
    );
  }
}

PendingCornered _requirePendingCornered(MatchState state) {
  final pending = state.pendingCornered;
  if (pending == null) {
    throw const EngineException(
      'INVALID_PHASE',
      'Cornered resolution requires pending context',
    );
  }
  return pending;
}

bool isEligibleAccuser(
  MatchState state,
  String playerId,
  String targetPlayerId,
) {
  final player = state.players[playerId];
  final evidence = player?.evidence[targetPlayerId];
  return player?.status == PlayerStatus.active &&
      player!.hearts > 0 &&
      player.role == PlayerRole.innocent &&
      !player.accusationUsed &&
      !state.accusationUsed.contains(playerId) &&
      evidence?.clue == true &&
      evidence?.behavior == true;
}

List<String> _buildAccusationOrder(MatchState state, PendingCornered pending) {
  final attackerIndex = state.seatOrder.indexOf(pending.attackerPlayerId);
  if (attackerIndex < 0) {
    throw const EngineException('INVALID_PLAYER', 'Attacker must have a seat');
  }
  final order = <String>[];
  for (var offset = 0; offset < state.seatOrder.length; offset++) {
    final id =
        state.seatOrder[(attackerIndex + offset) % state.seatOrder.length];
    final player = state.players[id];
    if (player?.status == PlayerStatus.active && player!.hearts > 0) {
      order.add(id);
    }
  }
  return order;
}

String? _currentAccuser(MatchState state) {
  if (state.phase != TurnPhase.awaitingAccusation ||
      state.pendingCornered == null) {
    return null;
  }
  final pending = state.pendingCornered!;
  if (pending.accusationIndex >= pending.accusationOrderPlayerIds.length) {
    return null;
  }
  return pending.accusationOrderPlayerIds[pending.accusationIndex];
}

String? currentAccusationPlayerId(MatchState state) => _currentAccuser(state);

String? currentLastChancePlayerId(MatchState state) =>
    state.phase == TurnPhase.awaitingLastChance && state.pendingCornered != null
    ? state.pendingCornered!.targetPlayerId
    : null;

MatchState beginCorneredResolution(MatchState state, int nowMs) {
  if (state.phase != TurnPhase.awaitingAccusation ||
      state.pendingCornered == null) {
    throw const EngineException(
      'INVALID_PHASE',
      'Cornered resolution can only begin after a player is Cornered',
    );
  }
  final pending = state.pendingCornered!;
  if (state.deadlineUtc != null ||
      pending.accusationOrderPlayerIds.isNotEmpty ||
      pending.accusationIndex != 0 ||
      pending.secretFinishResolved) {
    throw const EngineException(
      'INVALID_PHASE',
      'Cornered resolution has already started',
    );
  }
  final order = _buildAccusationOrder(state, pending);
  final ordered = state.copyWith(
    pendingCornered: pending.copyWith(
      accusationOrderPlayerIds: order,
      accusationIndex: 0,
      accusationPassed: false,
      secretFinishResolved: false,
      clearLastChanceChoice: true,
    ),
  );
  if (order.isEmpty) return _openSecretFinishWindow(ordered, nowMs);
  return ordered.copyWith(
    deadlineUtc: _deadlineFromNow(nowMs, accusationOfferMs),
  );
}

MatchState _openSecretFinishWindow(MatchState state, int nowMs) {
  final pending = _requirePendingCornered(state);
  final target = state.players[pending.targetPlayerId];
  if (target == null || target.status != PlayerStatus.cornered) {
    throw const EngineException(
      'INVALID_TARGET',
      'Secret Finish requires a surviving Cornered target',
    );
  }
  final eligible = [
    for (final id in state.seatOrder)
      if (state.players[id]?.status == PlayerStatus.active &&
          state.players[id]!.hearts > 0)
        id,
  ];
  return state.copyWith(
    phase: TurnPhase.awaitingSecretFinish,
    deadlineUtc: _deadlineFromNow(nowMs, secretFinishWindowMs),
    pendingSecretFinish: PendingSecretFinish(
      targetPlayerId: pending.targetPlayerId,
      eligiblePlayerIds: eligible,
      submissions: const {},
    ),
  );
}

MatchState _openLastChanceWindow(MatchState state, int nowMs) {
  final pending = _requirePendingCornered(state);
  final target = state.players[pending.targetPlayerId];
  if (target == null || target.status != PlayerStatus.cornered) {
    throw const EngineException(
      'INVALID_TARGET',
      'Last Chance requires a surviving Cornered target',
    );
  }
  return state.copyWith(
    phase: TurnPhase.awaitingLastChance,
    deadlineUtc: _deadlineFromNow(nowMs, lastChanceWindowMs),
    clearPendingSecretFinish: true,
    pendingCornered: pending.copyWith(
      secretFinishResolved: true,
      clearLastChanceChoice: true,
    ),
  );
}

MatchState _passCurrentAccusation(MatchState state, int nowMs) {
  final pending = _requirePendingCornered(state);
  final nextIndex = pending.accusationIndex + 1;
  final next = state.copyWith(
    version: state.version + 1,
    pendingCornered: pending.copyWith(
      accusationIndex: nextIndex,
      accusationPassed: false,
    ),
  );
  if (nextIndex >= pending.accusationOrderPlayerIds.length) {
    return _openSecretFinishWindow(next, nowMs);
  }
  return next.copyWith(deadlineUtc: _deadlineFromNow(nowMs, accusationOfferMs));
}

MatchState resumeInterruptedTurn(MatchState state) {
  final version = state.version;
  final resumed = state.copyWith(
    phase: TurnPhase.activeTurn,
    clearDeadlineUtc: true,
    clearPendingAttack: true,
    clearPendingCardEffect: true,
    clearPendingCornered: true,
    clearPendingSecretFinish: true,
  );
  final currentPlayerId = resumed.currentPlayerId;
  if (currentPlayerId == null) {
    throw const EngineException(
      'INVALID_PLAYER',
      'Interrupted turn must have an owner',
    );
  }
  final owner = resumed.players[currentPlayerId];
  if (owner?.status == PlayerStatus.active) return resumed;
  if (owner?.status != PlayerStatus.eliminated) {
    throw const EngineException(
      'NOT_ELIGIBLE',
      'Interrupted turn owner must be Active or eliminated',
    );
  }
  return advanceTurnAfterElimination(resumed).copyWith(version: version);
}

MatchState _resolveAccusation(MatchState state, String accuserPlayerId) {
  final pending = _requirePendingCornered(state);
  final accuser = state.players[accuserPlayerId];
  final suspect = state.players[pending.targetPlayerId];
  if (accuser == null ||
      suspect == null ||
      !isEligibleAccuser(state, accuserPlayerId, pending.targetPlayerId) ||
      suspect.status != PlayerStatus.cornered ||
      (suspect.role != PlayerRole.innocent &&
          suspect.role != PlayerRole.impostor)) {
    throw const EngineException(
      'INVALID_ACCUSATION',
      'Current player is not eligible to accuse this Cornered suspect',
    );
  }
  final used = state.accusationUsed.contains(accuserPlayerId)
      ? state.accusationUsed
      : [...state.accusationUsed, accuserPlayerId];
  final players = {
    ...state.players,
    accuserPlayerId: accuser.copyWith(accusationUsed: true),
  };
  if (suspect.role == PlayerRole.impostor) {
    return state.copyWith(
      version: state.version + 1,
      phase: TurnPhase.finished,
      clearCurrentPlayerId: true,
      clearDeadlineUtc: true,
      players: players,
      accusationUsed: used,
      clearPendingAttack: true,
      clearPendingCornered: true,
      clearPendingSecretFinish: true,
      winner: MatchOutcome.winner(accuserPlayerId),
    );
  }
  final eliminated = state.copyWith(
    version: state.version + 1,
    phase: TurnPhase.activeTurn,
    clearDeadlineUtc: true,
    players: {
      ...players,
      accuserPlayerId: players[accuserPlayerId]!.copyWith(
        status: PlayerStatus.eliminated,
      ),
      pending.targetPlayerId: suspect.copyWith(status: PlayerStatus.eliminated),
    },
    accusationUsed: used,
    clearPendingAttack: true,
    clearPendingCornered: true,
    clearPendingSecretFinish: true,
  );
  final winner = findImpostorWinner(eliminated);
  return winner ?? resumeInterruptedTurn(eliminated);
}

MatchState respondToAccusation(
  MatchState state,
  String playerId,
  AccusationResponse response,
  int nowMs,
) {
  if (state.phase != TurnPhase.awaitingAccusation ||
      state.pendingCornered == null) {
    throw const EngineException(
      'INVALID_PHASE',
      'There is no active accusation offer',
    );
  }
  final current = _currentAccuser(state);
  if (current != playerId) {
    throw const EngineException(
      'NOT_YOUR_TURN',
      'Only the current accusation-slot player may respond',
    );
  }
  _requireWindowOpen(state, nowMs);
  final pending = state.pendingCornered!;
  if (pending.accusationPassed) {
    throw const EngineException(
      'INVALID_ACCUSATION',
      'The current response was already submitted',
    );
  }
  if (response.kind == AccusationResponseKind.pass) {
    return state.copyWith(
      version: state.version + 1,
      pendingCornered: pending.copyWith(accusationPassed: true),
    );
  }
  return _resolveAccusation(state, playerId);
}

MatchState expireAccusationOffer(MatchState state, int nowMs) {
  if (state.phase != TurnPhase.awaitingAccusation ||
      state.pendingCornered == null) {
    throw const EngineException(
      'INVALID_PHASE',
      'There is no active accusation offer to expire',
    );
  }
  if (_currentAccuser(state) == null) {
    throw const EngineException(
      'INVALID_ACCUSATION',
      'There is no player awaiting an accusation offer',
    );
  }
  _requireWindowExpired(state, nowMs);
  return _passCurrentAccusation(state, nowMs);
}

MatchState submitSecretFinishChoice(
  MatchState state,
  String playerId,
  String choice,
  int nowMs,
) {
  if (state.phase != TurnPhase.awaitingSecretFinish ||
      state.pendingSecretFinish == null) {
    throw const EngineException(
      'INVALID_PHASE',
      'There is no active Secret Finish window',
    );
  }
  if (choice != 'finish' && choice != 'pass') {
    throw const EngineException(
      'INVALID_SECRET_FINISH',
      'Secret Finish choice must be finish or pass',
    );
  }
  _requireWindowOpen(state, nowMs);
  final pending = state.pendingSecretFinish!;
  if (!pending.eligiblePlayerIds.contains(playerId) ||
      pending.submissions.containsKey(playerId)) {
    throw const EngineException(
      'NOT_ELIGIBLE',
      'Secret Finish choice is not valid for this player',
    );
  }
  if (choice == 'finish') {
    final player = state.players[playerId];
    final target = state.players[pending.targetPlayerId];
    if (player?.role != PlayerRole.impostor ||
        player?.status != PlayerStatus.active ||
        target?.role != PlayerRole.innocent ||
        target?.status != PlayerStatus.cornered) {
      throw const EngineException(
        'NOT_ELIGIBLE',
        'Secret Finish choice is not valid for this player',
      );
    }
  }
  return state.copyWith(
    version: state.version + 1,
    pendingSecretFinish: PendingSecretFinish(
      targetPlayerId: pending.targetPlayerId,
      eligiblePlayerIds: pending.eligiblePlayerIds,
      submissions: {...pending.submissions, playerId: choice},
    ),
  );
}

MatchState _resolveSecretFinishWindow(MatchState state, int nowMs) {
  final pending = state.pendingSecretFinish;
  final cornered = _requirePendingCornered(state);
  if (state.phase != TurnPhase.awaitingSecretFinish || pending == null) {
    throw const EngineException(
      'INVALID_PHASE',
      'There is no active Secret Finish window',
    );
  }
  final finishers = pending.submissions.entries
      .where((entry) => entry.value == 'finish')
      .map((entry) => entry.key)
      .toList();
  if (finishers.length > 1) {
    throw const EngineException(
      'INVALID_SECRET_FINISH',
      'Only one authorized Secret Finish may be submitted',
    );
  }
  if (finishers.isEmpty) {
    final passed = state.copyWith(
      pendingCornered: cornered.copyWith(secretFinishResolved: true),
      clearPendingSecretFinish: true,
      clearDeadlineUtc: true,
    );
    return _openLastChanceWindow(passed, nowMs);
  }
  final impostorId = finishers.single;
  final impostor = state.players[impostorId];
  final target = state.players[pending.targetPlayerId];
  if (!pending.eligiblePlayerIds.contains(impostorId) ||
      impostor?.role != PlayerRole.impostor ||
      impostor?.status != PlayerStatus.active ||
      target?.role != PlayerRole.innocent ||
      target?.status != PlayerStatus.cornered) {
    throw const EngineException(
      'INVALID_SECRET_FINISH',
      'Submitted Secret Finish is not valid for this window',
    );
  }
  final eliminated = state.copyWith(
    phase: TurnPhase.activeTurn,
    clearDeadlineUtc: true,
    players: {
      ...state.players,
      target!.playerId: target.copyWith(status: PlayerStatus.eliminated),
    },
    clearPendingSecretFinish: true,
    pendingCornered: cornered.copyWith(secretFinishResolved: true),
  );
  final winner = findImpostorWinner(eliminated);
  return winner ?? resumeInterruptedTurn(eliminated);
}

MatchState expireSecretFinishWindow(MatchState state, int nowMs) {
  if (state.phase != TurnPhase.awaitingSecretFinish ||
      state.pendingSecretFinish == null) {
    throw const EngineException(
      'INVALID_PHASE',
      'There is no active Secret Finish window to expire',
    );
  }
  _requireWindowExpired(state, nowMs);
  return _resolveSecretFinishWindow(
    state.copyWith(version: state.version + 1),
    nowMs,
  );
}

PendingCornered _requireLastChanceTarget(MatchState state, String playerId) {
  final pending = state.pendingCornered;
  final target = pending == null ? null : state.players[pending.targetPlayerId];
  if (state.phase != TurnPhase.awaitingLastChance ||
      pending == null ||
      !pending.secretFinishResolved ||
      currentLastChancePlayerId(state) != playerId ||
      target?.status != PlayerStatus.cornered) {
    throw const EngineException(
      'INVALID_PHASE',
      'Last Chance requires its surviving Cornered target after Secret Finish',
    );
  }
  return pending;
}

MatchState playLastChance(
  MatchState state,
  String playerId,
  String cardInstanceId,
  int nowMs,
) {
  final pending = _requireLastChanceTarget(state, playerId);
  _requireWindowOpen(state, nowMs);
  if (pending.lastChanceChoice != null) {
    throw const EngineException(
      'INVALID_REACTION',
      'Last Chance response was already submitted',
    );
  }
  final target = state.players[playerId]!;
  if (_cardDesignId(cardInstanceId) != 'card_19' ||
      !target.hand.contains(cardInstanceId)) {
    throw const EngineException(
      'INVALID_CARD',
      'Last Chance must be in the Cornered target hand',
    );
  }
  return state.copyWith(
    version: state.version + 1,
    pendingCornered: pending.copyWith(
      lastChanceChoice: LastChanceChoice.play(cardInstanceId),
    ),
  );
}

MatchState passLastChance(MatchState state, String playerId, int nowMs) {
  final pending = _requireLastChanceTarget(state, playerId);
  _requireWindowOpen(state, nowMs);
  if (pending.lastChanceChoice != null) {
    throw const EngineException(
      'INVALID_REACTION',
      'Last Chance response was already submitted',
    );
  }
  return state.copyWith(
    version: state.version + 1,
    pendingCornered: pending.copyWith(
      lastChanceChoice: const LastChanceChoice.pass(),
    ),
  );
}

MatchState expireLastChanceWindow(MatchState state, int nowMs) {
  final pending = _requirePendingCornered(state);
  _requireLastChanceTarget(state, pending.targetPlayerId);
  _requireWindowExpired(state, nowMs);
  final target = state.players[pending.targetPlayerId]!;
  final choice = pending.lastChanceChoice;
  var resolved = state;
  if (choice?.kind == 'play') {
    final card = choice!.cardInstanceId!;
    if (!target.hand.contains(card) || _cardDesignId(card) != 'card_19') {
      throw const EngineException(
        'INVALID_CARD',
        'Selected Last Chance is no longer in the target hand',
      );
    }
    resolved = state.copyWith(
      version: state.version + 1,
      players: {
        ...state.players,
        target.playerId: target.copyWith(
          status: PlayerStatus.active,
          hearts: 1,
          hand: target.hand.where((instance) => instance != card).toList(),
        ),
      },
      discardPile: [...state.discardPile, card],
    );
  } else {
    resolved = state.copyWith(version: state.version + 1);
  }
  return resumeInterruptedTurn(resolved);
}
