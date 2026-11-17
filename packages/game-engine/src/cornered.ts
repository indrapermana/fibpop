import { getCardDesignId } from './card-instance.js';
import { EngineError } from './errors.js';
import {
  matchStateSchema,
  type MatchState,
  type PendingCornered,
} from './state.js';
import { advanceTurnAfterElimination } from './turns.js';

export const ACCUSATION_OFFER_MS = 10_000;
export const SECRET_FINISH_WINDOW_MS = 10_000;

export type AccusationResponse = { kind: 'pass' } | { kind: 'accuse' };

export type SecretFinishChoice = 'finish' | 'pass';

function requirePendingCornered(state: MatchState): PendingCornered {
  if (!state.pendingCornered) {
    throw new EngineError(
      'INVALID_PHASE',
      'A Cornered resolution requires pending Cornered context',
    );
  }

  return state.pendingCornered;
}

function deadlineFromNow(nowMs: number, durationMs: number): string {
  if (!Number.isSafeInteger(nowMs) || nowMs < 0) {
    throw new EngineError(
      'INVALID_DEADLINE',
      'A finite epoch-millisecond timestamp is required',
    );
  }

  const deadline = new Date(nowMs + durationMs);
  if (!Number.isFinite(deadline.getTime())) {
    throw new EngineError(
      'INVALID_DEADLINE',
      'The response window deadline is outside the supported time range',
    );
  }

  return deadline.toISOString();
}

function requireWindowOpen(state: MatchState, nowMs: number): void {
  if (!Number.isSafeInteger(nowMs) || nowMs < 0 || state.deadlineUtc === null) {
    throw new EngineError(
      'INVALID_DEADLINE',
      'A timestamp and active window deadline are required',
    );
  }

  if (nowMs >= Date.parse(state.deadlineUtc)) {
    throw new EngineError('WINDOW_EXPIRED', 'The response window has expired');
  }
}

function requireWindowExpired(state: MatchState, nowMs: number): void {
  if (!Number.isSafeInteger(nowMs) || nowMs < 0 || state.deadlineUtc === null) {
    throw new EngineError(
      'INVALID_DEADLINE',
      'A timestamp and active window deadline are required',
    );
  }

  if (nowMs < Date.parse(state.deadlineUtc)) {
    throw new EngineError(
      'WINDOW_NOT_EXPIRED',
      'The response window has not expired',
    );
  }
}

function isEligibleAccuser(
  state: MatchState,
  playerId: string,
  targetPlayerId: string,
): boolean {
  const player = state.players[playerId];
  const evidence = player?.evidence[targetPlayerId];
  return (
    player?.status === 'active' &&
    player.hearts > 0 &&
    player.role === 'innocent' &&
    !player.accusationUsed &&
    !state.accusationUsed.includes(playerId) &&
    evidence?.clue === true &&
    evidence.behavior === true
  );
}

function buildAccusationOrder(
  state: MatchState,
  pending: PendingCornered,
): string[] {
  const attackerSeatIndex = state.seatOrder.indexOf(pending.attackerPlayerId);
  if (attackerSeatIndex < 0) {
    throw new EngineError(
      'INVALID_PLAYER',
      'The attacking player must have a seat',
    );
  }

  const eligiblePlayerIds = new Set(
    state.seatOrder.filter((playerId) =>
      isEligibleAccuser(state, playerId, pending.targetPlayerId),
    ),
  );
  const order: string[] = [];

  if (eligiblePlayerIds.has(pending.attackerPlayerId)) {
    order.push(pending.attackerPlayerId);
  }

  for (let offset = 1; offset < state.seatOrder.length; offset += 1) {
    const playerId =
      state.seatOrder[(attackerSeatIndex + offset) % state.seatOrder.length];
    if (eligiblePlayerIds.has(playerId)) {
      order.push(playerId);
    }
  }

  return order;
}

function currentAccuser(state: MatchState): string | null {
  if (state.phase !== 'awaiting_accusation' || !state.pendingCornered) {
    return null;
  }

  return (
    state.pendingCornered.accusationOrderPlayerIds[
      state.pendingCornered.accusationIndex
    ] ?? null
  );
}

function findImpostorWinner(state: MatchState): MatchState | null {
  const impostor = Object.values(state.players).find(
    (player) => player.role === 'impostor',
  );
  if (
    !impostor ||
    impostor.status === 'eliminated' ||
    Object.values(state.players).some(
      (player) => player.role === 'innocent' && player.status !== 'eliminated',
    )
  ) {
    return null;
  }

  return matchStateSchema.parse({
    ...state,
    phase: 'finished',
    currentPlayerId: null,
    deadlineUtc: null,
    pendingAttack: null,
    pendingCardEffect: null,
    pendingCornered: null,
    pendingSecretFinish: null,
    winner: { kind: 'winner', playerId: impostor.playerId },
  });
}

function resumeInterruptedTurn(state: MatchState): MatchState {
  const version = state.version;
  const resumed = matchStateSchema.parse({
    ...state,
    phase: 'active_turn',
    deadlineUtc: null,
    pendingAttack: null,
    pendingCardEffect: null,
    pendingCornered: null,
    pendingSecretFinish: null,
  });
  const currentPlayerId = resumed.currentPlayerId;
  if (currentPlayerId === null) {
    throw new EngineError(
      'INVALID_PLAYER',
      'The interrupted turn must have an owner',
    );
  }

  const turnOwner = resumed.players[currentPlayerId];
  if (turnOwner?.status === 'active') {
    return resumed;
  }

  if (turnOwner?.status !== 'eliminated') {
    throw new EngineError(
      'NOT_ELIGIBLE',
      'The interrupted turn owner must be Active or eliminated',
    );
  }

  const advanced = advanceTurnAfterElimination(resumed);
  return matchStateSchema.parse({ ...advanced, version });
}

function openLastChanceOrResume(state: MatchState): MatchState {
  const pending = requirePendingCornered(state);
  const target = state.players[pending.targetPlayerId];
  if (!target || target.status !== 'cornered') {
    throw new EngineError(
      'INVALID_TARGET',
      'Last Chance requires a surviving Cornered target',
    );
  }

  const readyState = matchStateSchema.parse({
    ...state,
    phase: 'active_turn',
    deadlineUtc: null,
    pendingSecretFinish: null,
    pendingCornered: { ...pending, secretFinishResolved: true },
  });
  if (target.hand.some((card) => getCardDesignId(card) === 'card_19')) {
    return matchStateSchema.parse({
      ...readyState,
      phase: 'awaiting_last_chance',
    });
  }

  return resumeInterruptedTurn(readyState);
}

function openSecretFinishWindow(state: MatchState, nowMs: number): MatchState {
  const pending = requirePendingCornered(state);
  const target = state.players[pending.targetPlayerId];
  if (!target || target.status !== 'cornered') {
    throw new EngineError(
      'INVALID_TARGET',
      'Secret Finish requires a surviving Cornered target',
    );
  }

  if (target.role !== 'innocent') {
    return openLastChanceOrResume(
      matchStateSchema.parse({
        ...state,
        pendingCornered: { ...pending, secretFinishResolved: true },
      }),
    );
  }

  const eligiblePlayerIds = state.seatOrder.filter((playerId) => {
    const player = state.players[playerId];
    return player?.status === 'active' && player.hearts > 0;
  });
  if (eligiblePlayerIds.length === 0) {
    return openLastChanceOrResume(
      matchStateSchema.parse({
        ...state,
        pendingCornered: { ...pending, secretFinishResolved: true },
      }),
    );
  }

  return matchStateSchema.parse({
    ...state,
    phase: 'awaiting_secret_finish',
    deadlineUtc: deadlineFromNow(nowMs, SECRET_FINISH_WINDOW_MS),
    pendingSecretFinish: {
      targetPlayerId: pending.targetPlayerId,
      eligiblePlayerIds,
      submissions: {},
    },
  });
}

export function beginCorneredResolution(
  state: MatchState,
  nowMs: number,
): MatchState {
  if (state.phase !== 'awaiting_accusation' || !state.pendingCornered) {
    throw new EngineError(
      'INVALID_PHASE',
      'Cornered resolution can only begin after a player is Cornered',
    );
  }

  const pending = state.pendingCornered;
  if (
    state.deadlineUtc !== null ||
    pending.accusationOrderPlayerIds.length > 0 ||
    pending.accusationIndex !== 0 ||
    pending.secretFinishResolved
  ) {
    throw new EngineError(
      'INVALID_PHASE',
      'Cornered resolution has already started',
    );
  }

  const accusationOrderPlayerIds = buildAccusationOrder(state, pending);
  const orderedState = matchStateSchema.parse({
    ...state,
    pendingCornered: {
      ...pending,
      accusationOrderPlayerIds,
      accusationIndex: 0,
      secretFinishResolved: false,
    },
  });

  if (accusationOrderPlayerIds.length === 0) {
    return openSecretFinishWindow(orderedState, nowMs);
  }

  return matchStateSchema.parse({
    ...orderedState,
    deadlineUtc: deadlineFromNow(nowMs, ACCUSATION_OFFER_MS),
  });
}

export function currentAccusationPlayerId(state: MatchState): string | null {
  return currentAccuser(state);
}

function passCurrentAccusation(state: MatchState, nowMs: number): MatchState {
  const pending = requirePendingCornered(state);
  const nextIndex = pending.accusationIndex + 1;
  const nextState = matchStateSchema.parse({
    ...state,
    version: state.version + 1,
    pendingCornered: { ...pending, accusationIndex: nextIndex },
  });

  if (nextIndex >= pending.accusationOrderPlayerIds.length) {
    return openSecretFinishWindow(nextState, nowMs);
  }

  return matchStateSchema.parse({
    ...nextState,
    deadlineUtc: deadlineFromNow(nowMs, ACCUSATION_OFFER_MS),
  });
}

function markAccusationUsed(
  state: MatchState,
  accuserPlayerId: string,
): MatchState['players'] {
  const accuser = state.players[accuserPlayerId];
  return {
    ...state.players,
    [accuserPlayerId]: { ...accuser, accusationUsed: true },
  };
}

function resolveAccusation(
  state: MatchState,
  accuserPlayerId: string,
): MatchState {
  const pending = requirePendingCornered(state);
  const accuser = state.players[accuserPlayerId];
  const suspect = state.players[pending.targetPlayerId];
  if (
    !accuser ||
    !suspect ||
    !isEligibleAccuser(state, accuserPlayerId, pending.targetPlayerId) ||
    suspect.status !== 'cornered' ||
    (suspect.role !== 'innocent' && suspect.role !== 'impostor')
  ) {
    throw new EngineError(
      'INVALID_ACCUSATION',
      'The current player is not eligible to accuse this Cornered suspect',
    );
  }

  const usedAccusationIds = state.accusationUsed.includes(accuserPlayerId)
    ? state.accusationUsed
    : [...state.accusationUsed, accuserPlayerId];
  const players = markAccusationUsed(state, accuserPlayerId);
  if (suspect.role === 'impostor') {
    return matchStateSchema.parse({
      ...state,
      version: state.version + 1,
      phase: 'finished',
      currentPlayerId: null,
      deadlineUtc: null,
      players,
      pendingAttack: null,
      pendingCardEffect: null,
      pendingCornered: null,
      pendingSecretFinish: null,
      accusationUsed: usedAccusationIds,
      winner: { kind: 'winner', playerId: accuserPlayerId },
    });
  }

  const updatedPlayers = {
    ...players,
    [accuserPlayerId]: {
      ...players[accuserPlayerId],
      status: 'eliminated' as const,
    },
    [pending.targetPlayerId]: {
      ...suspect,
      status: 'eliminated' as const,
    },
  };
  const eliminatedState = matchStateSchema.parse({
    ...state,
    version: state.version + 1,
    phase: 'active_turn',
    deadlineUtc: null,
    players: updatedPlayers,
    pendingAttack: null,
    pendingCardEffect: null,
    pendingCornered: null,
    pendingSecretFinish: null,
    accusationUsed: usedAccusationIds,
  });
  const winnerState = findImpostorWinner(eliminatedState);
  if (winnerState) {
    return winnerState;
  }

  if (eliminatedState.currentPlayerId === accuserPlayerId) {
    return resumeInterruptedTurn(eliminatedState);
  }

  return eliminatedState;
}

export function respondToAccusation(
  state: MatchState,
  playerId: string,
  response: AccusationResponse,
  nowMs: number,
): MatchState {
  if (state.phase !== 'awaiting_accusation' || !state.pendingCornered) {
    throw new EngineError(
      'INVALID_PHASE',
      'There is no active accusation offer',
    );
  }

  if (!response || (response.kind !== 'pass' && response.kind !== 'accuse')) {
    throw new EngineError(
      'INVALID_ACCUSATION',
      'The accusation response must be pass or accuse',
    );
  }

  if (currentAccuser(state) !== playerId) {
    throw new EngineError(
      'NOT_YOUR_TURN',
      'Only the current eligible Innocent may answer the accusation offer',
    );
  }

  requireWindowOpen(state, nowMs);
  if (response.kind === 'pass') {
    return passCurrentAccusation(state, nowMs);
  }

  return resolveAccusation(state, playerId);
}

export function expireAccusationOffer(
  state: MatchState,
  nowMs: number,
): MatchState {
  if (state.phase !== 'awaiting_accusation' || !state.pendingCornered) {
    throw new EngineError(
      'INVALID_PHASE',
      'There is no active accusation offer to expire',
    );
  }

  if (currentAccuser(state) === null) {
    throw new EngineError(
      'INVALID_ACCUSATION',
      'There is no eligible player awaiting an accusation offer',
    );
  }

  requireWindowExpired(state, nowMs);
  return passCurrentAccusation(state, nowMs);
}

function resolveSecretFinishWindow(state: MatchState): MatchState {
  const pendingSecretFinish = state.pendingSecretFinish;
  const pendingCornered = requirePendingCornered(state);
  if (!pendingSecretFinish || state.phase !== 'awaiting_secret_finish') {
    throw new EngineError(
      'INVALID_PHASE',
      'There is no active Secret Finish window',
    );
  }

  const finishSubmitters = Object.entries(
    pendingSecretFinish.submissions,
  ).filter(([, choice]) => choice === 'finish');
  if (finishSubmitters.length > 1) {
    throw new EngineError(
      'INVALID_SECRET_FINISH',
      'Only one authorized Secret Finish may be submitted',
    );
  }

  if (finishSubmitters.length === 0) {
    return openLastChanceOrResume(
      matchStateSchema.parse({
        ...state,
        pendingCornered: {
          ...pendingCornered,
          secretFinishResolved: true,
        },
        pendingSecretFinish: null,
        deadlineUtc: null,
      }),
    );
  }

  const [impostorPlayerId] = finishSubmitters[0] ?? [];
  const impostor = impostorPlayerId ? state.players[impostorPlayerId] : null;
  const target = state.players[pendingSecretFinish.targetPlayerId];
  if (
    !impostor ||
    !target ||
    !pendingSecretFinish.eligiblePlayerIds.includes(impostorPlayerId) ||
    impostor.role !== 'impostor' ||
    impostor.status !== 'active' ||
    target.role !== 'innocent' ||
    target.status !== 'cornered'
  ) {
    throw new EngineError(
      'INVALID_SECRET_FINISH',
      'The submitted Secret Finish is not valid for this window',
    );
  }

  const eliminatedState = matchStateSchema.parse({
    ...state,
    phase: 'active_turn',
    deadlineUtc: null,
    players: {
      ...state.players,
      [target.playerId]: { ...target, status: 'eliminated' },
    },
    pendingSecretFinish: null,
    pendingCornered: {
      ...pendingCornered,
      secretFinishResolved: true,
    },
  });
  const winnerState = findImpostorWinner(eliminatedState);
  return winnerState ?? resumeInterruptedTurn(eliminatedState);
}

export function submitSecretFinishChoice(
  state: MatchState,
  playerId: string,
  choice: SecretFinishChoice,
  nowMs: number,
): MatchState {
  if (state.phase !== 'awaiting_secret_finish' || !state.pendingSecretFinish) {
    throw new EngineError(
      'INVALID_PHASE',
      'There is no active Secret Finish window',
    );
  }

  if (choice !== 'finish' && choice !== 'pass') {
    throw new EngineError(
      'INVALID_SECRET_FINISH',
      'The Secret Finish choice must be finish or pass',
    );
  }

  requireWindowOpen(state, nowMs);
  const pending = state.pendingSecretFinish;
  if (
    !pending.eligiblePlayerIds.includes(playerId) ||
    Object.hasOwn(pending.submissions, playerId)
  ) {
    throw new EngineError(
      'NOT_ELIGIBLE',
      'The submitted Secret Finish choice is not valid for this player',
    );
  }

  if (choice === 'finish') {
    const player = state.players[playerId];
    const target = state.players[pending.targetPlayerId];
    if (
      player?.role !== 'impostor' ||
      player.status !== 'active' ||
      target?.role !== 'innocent' ||
      target.status !== 'cornered'
    ) {
      throw new EngineError(
        'NOT_ELIGIBLE',
        'The submitted Secret Finish choice is not valid for this player',
      );
    }
  }

  const submissions = { ...pending.submissions, [playerId]: choice };
  const submittedState = matchStateSchema.parse({
    ...state,
    version: state.version + 1,
    pendingSecretFinish: { ...pending, submissions },
  });
  if (
    pending.eligiblePlayerIds.every((eligibleId) => eligibleId in submissions)
  ) {
    return resolveSecretFinishWindow(submittedState);
  }

  return submittedState;
}

export function expireSecretFinishWindow(
  state: MatchState,
  nowMs: number,
): MatchState {
  if (state.phase !== 'awaiting_secret_finish' || !state.pendingSecretFinish) {
    throw new EngineError(
      'INVALID_PHASE',
      'There is no active Secret Finish window to expire',
    );
  }

  requireWindowExpired(state, nowMs);
  const timedOutState = matchStateSchema.parse({
    ...state,
    version: state.version + 1,
  });
  return resolveSecretFinishWindow(timedOutState);
}

export function currentLastChancePlayerId(state: MatchState): string | null {
  return state.phase === 'awaiting_last_chance' && state.pendingCornered
    ? state.pendingCornered.targetPlayerId
    : null;
}

function requireLastChanceTarget(
  state: MatchState,
  playerId: string,
): PendingCornered {
  const pending = state.pendingCornered;
  const target = pending ? state.players[pending.targetPlayerId] : null;
  if (
    state.phase !== 'awaiting_last_chance' ||
    !pending ||
    !pending.secretFinishResolved ||
    currentLastChancePlayerId(state) !== playerId ||
    target?.status !== 'cornered'
  ) {
    throw new EngineError(
      'INVALID_PHASE',
      'Last Chance is only available to its surviving Cornered target after a no-finish window',
    );
  }

  return pending;
}

export function playLastChance(
  state: MatchState,
  playerId: string,
  cardInstanceId: string,
): MatchState {
  requireLastChanceTarget(state, playerId);
  const target = state.players[playerId];
  if (
    getCardDesignId(cardInstanceId) !== 'card_19' ||
    !target.hand.includes(cardInstanceId)
  ) {
    throw new EngineError(
      'INVALID_CARD',
      'Last Chance must be in the Cornered target hand',
    );
  }

  return matchStateSchema.parse({
    ...state,
    version: state.version + 1,
    phase: 'active_turn',
    deadlineUtc: null,
    players: {
      ...state.players,
      [playerId]: {
        ...target,
        status: 'active',
        hearts: 1,
        hand: target.hand.filter((card) => card !== cardInstanceId),
      },
    },
    discardPile: [...state.discardPile, cardInstanceId],
    pendingCornered: null,
    pendingSecretFinish: null,
  });
}

export function passLastChance(
  state: MatchState,
  playerId: string,
): MatchState {
  requireLastChanceTarget(state, playerId);
  const passedState = matchStateSchema.parse({
    ...state,
    version: state.version + 1,
    phase: 'active_turn',
  });
  return resumeInterruptedTurn(passedState);
}
