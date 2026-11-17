import { playActionCard } from './action-card.js';
import { validateAttackTarget } from './commands.js';
import { getCardDesignId } from './card-instance.js';
import { beginCorneredResolution } from './cornered.js';
import { EngineError } from './errors.js';
import { grantEvidence } from './investigations.js';
import { matchStateSchema, type MatchState } from './state.js';
import {
  hasBehaviorEvidenceQualifyingAction,
  recordSuccessfulAttackDamage,
} from './suspicion.js';

const attackCardIds = new Set(['card_01', 'card_02', 'card_03', 'card_04']);
const targetDefenseCardIds = new Set(['card_05', 'card_06', 'card_08']);
const stepInCardId = 'card_07';
const safePlaceCardId = 'card_21';

export type AttackResponse =
  | { kind: 'pass'; discardCardInstanceId?: string }
  | { kind: 'defend'; cardInstanceId: string }
  | { kind: 'step_in'; cardInstanceId: string };

function requireCardInHand(
  state: MatchState,
  playerId: string,
  cardInstanceId: string,
  allowedDesignIds: Set<string>,
): string {
  const player = state.players[playerId];
  if (!player || !player.hand.includes(cardInstanceId)) {
    throw new EngineError(
      'INVALID_CARD',
      'The card must be in the player hand',
    );
  }

  const designId = getCardDesignId(cardInstanceId);
  if (designId === null || !allowedDesignIds.has(designId)) {
    throw new EngineError(
      'INVALID_CARD',
      'The card is not valid for this action',
    );
  }

  return designId;
}

function buildStepInOrder(state: MatchState, targetPlayerId: string): string[] {
  const targetSeatIndex = state.seatOrder.indexOf(targetPlayerId);
  const stepInPlayerIds: string[] = [];

  for (let offset = 1; offset < state.seatOrder.length; offset += 1) {
    const playerId =
      state.seatOrder[(targetSeatIndex + offset) % state.seatOrder.length];
    const player = state.players[playerId];
    if (player?.status === 'active' && player.hearts > 0) {
      stepInPlayerIds.push(playerId);
    }
  }

  return stepInPlayerIds;
}

export function startAttack(
  state: MatchState,
  attackerPlayerId: string,
  targetPlayerId: string,
  attackCardInstanceId: string,
): MatchState {
  const targetValidation = validateAttackTarget(
    state,
    attackerPlayerId,
    targetPlayerId,
  );
  if (!targetValidation.ok) {
    throw new EngineError(
      targetValidation.error.code,
      targetValidation.error.message,
    );
  }

  const played = playActionCard(
    state,
    attackerPlayerId,
    attackCardInstanceId,
    attackCardIds,
    'attack',
  );

  const attackState = matchStateSchema.parse({
    ...played.state,
    phase: 'awaiting_reaction',
    pendingAttack: {
      attackerPlayerId,
      targetPlayerId,
      attackCardInstanceId,
      stepInPlayerIds: buildStepInOrder(state, targetPlayerId),
      stepInIndex: -1,
      targetDiscardCardInstanceId: null,
      calloutRevealedActionCardInstanceId:
        played.cardDesignId === 'card_03'
          ? state.players[targetPlayerId].lastPlayedActionCardInstanceId
          : null,
    },
    pendingCornered: null,
  });

  if (
    played.cardDesignId !== 'card_04' ||
    state.players[targetPlayerId].suspicion < 2 ||
    !hasBehaviorEvidenceQualifyingAction(state, targetPlayerId)
  ) {
    return attackState;
  }

  const withEvidence = grantEvidence(
    attackState,
    attackerPlayerId,
    targetPlayerId,
    'behavior',
  );
  return matchStateSchema.parse({
    ...withEvidence,
    version: state.version + 1,
  });
}

export function currentAttackResponder(state: MatchState): string | null {
  if (state.phase !== 'awaiting_reaction' || state.pendingAttack === null) {
    return null;
  }

  const pending = state.pendingAttack;
  if (pending.stepInIndex === -1) {
    return pending.targetPlayerId;
  }

  return pending.stepInPlayerIds[pending.stepInIndex] ?? null;
}

function resolveDamage(state: MatchState, nowMs?: number): MatchState {
  const pending = state.pendingAttack;
  if (!pending) {
    throw new EngineError('INVALID_REACTION', 'There is no attack to resolve');
  }

  const target = state.players[pending.targetPlayerId];
  if (!target || target.status !== 'active' || target.hearts < 1) {
    throw new EngineError(
      'INVALID_TARGET',
      'The pending attack target is no longer Active',
    );
  }

  const safePlaceIndex = state.activeEffects.findIndex(
    (effect) =>
      effect.type === 'safe_place' &&
      effect.targetPlayerId === pending.targetPlayerId,
  );
  if (safePlaceIndex >= 0) {
    return matchStateSchema.parse({
      ...state,
      version: state.version + 1,
      phase: 'active_turn',
      activeEffects: state.activeEffects.filter(
        (_, index) => index !== safePlaceIndex,
      ),
      pendingAttack: null,
    });
  }

  const targetDiscardCardInstanceId = pending.targetDiscardCardInstanceId;
  if (
    targetDiscardCardInstanceId !== null &&
    !target.hand.includes(targetDiscardCardInstanceId)
  ) {
    throw new EngineError(
      'INVALID_DISCARD',
      'The selected Double Down card must remain in the target hand',
    );
  }

  const hearts = target.hearts - 1;
  const cornered = hearts === 0;
  const players = {
    ...state.players,
    [pending.targetPlayerId]: {
      ...target,
      hand:
        targetDiscardCardInstanceId === null
          ? target.hand
          : target.hand.filter((card) => card !== targetDiscardCardInstanceId),
      hearts,
      status: cornered ? 'cornered' : 'active',
    },
  };
  const woundedState = matchStateSchema.parse({
    ...state,
    phase: cornered ? 'awaiting_accusation' : 'active_turn',
    players,
    pendingAttack: null,
    pendingCornered: cornered
      ? {
          attackerPlayerId: pending.attackerPlayerId,
          targetPlayerId: pending.targetPlayerId,
          attackCardInstanceId: pending.attackCardInstanceId,
          accusationOrderPlayerIds: [],
          accusationIndex: 0,
          secretFinishResolved: false,
        }
      : null,
    discardPile:
      targetDiscardCardInstanceId === null
        ? state.discardPile
        : [...state.discardPile, targetDiscardCardInstanceId],
  });
  const recordedState = recordSuccessfulAttackDamage(
    woundedState,
    pending.attackerPlayerId,
  );

  const resolvedState = matchStateSchema.parse({
    ...recordedState,
    version: state.version + 1,
  });
  if (!cornered) {
    return resolvedState;
  }

  if (nowMs === undefined) {
    throw new EngineError(
      'INVALID_DEADLINE',
      'A timestamp is required to open the Cornered accusation window',
    );
  }

  return beginCorneredResolution(resolvedState, nowMs);
}

function resolveDefense(
  state: MatchState,
  defenderPlayerId: string,
  cardInstanceId: string,
): MatchState {
  const pending = state.pendingAttack;
  if (!pending) {
    throw new EngineError('INVALID_REACTION', 'There is no attack to defend');
  }

  const designId = requireCardInHand(
    state,
    defenderPlayerId,
    cardInstanceId,
    targetDefenseCardIds,
  );
  const defender = state.players[defenderPlayerId];
  const players = {
    ...state.players,
    [defenderPlayerId]: {
      ...defender,
      hand: defender.hand.filter((card) => card !== cardInstanceId),
      suspicion:
        designId === 'card_06'
          ? Math.max(0, defender.suspicion - 1)
          : defender.suspicion,
    },
  };
  const defendedState = matchStateSchema.parse({
    ...state,
    version: state.version + 1,
    phase: 'active_turn',
    players,
    discardPile: [...state.discardPile, cardInstanceId],
    pendingAttack: null,
  });
  const evidenceAdded =
    designId === 'card_08' &&
    hasBehaviorEvidenceQualifyingAction(state, pending.attackerPlayerId);
  if (!evidenceAdded) {
    return defendedState;
  }

  const withEvidence = grantEvidence(
    defendedState,
    defenderPlayerId,
    pending.attackerPlayerId,
    'behavior',
  );
  return matchStateSchema.parse({
    ...withEvidence,
    version: state.version + 1,
  });
}

function resolveStepIn(
  state: MatchState,
  responderPlayerId: string,
  cardInstanceId: string,
): MatchState {
  requireCardInHand(
    state,
    responderPlayerId,
    cardInstanceId,
    new Set([stepInCardId]),
  );
  const responder = state.players[responderPlayerId];

  return matchStateSchema.parse({
    ...state,
    version: state.version + 1,
    phase: 'active_turn',
    players: {
      ...state.players,
      [responderPlayerId]: {
        ...responder,
        hand: responder.hand.filter((card) => card !== cardInstanceId),
      },
    },
    discardPile: [...state.discardPile, cardInstanceId],
    pendingAttack: null,
  });
}

export function respondToAttack(
  state: MatchState,
  responderPlayerId: string,
  response: AttackResponse,
  nowMs?: number,
): MatchState {
  if (state.phase !== 'awaiting_reaction' || state.pendingAttack === null) {
    throw new EngineError(
      'INVALID_PHASE',
      'Attack reactions require a pending attack',
    );
  }

  const pending = state.pendingAttack;
  const expectedResponder = currentAttackResponder(state);
  if (expectedResponder === null) {
    throw new EngineError('INVALID_REACTION', 'There is no eligible responder');
  }

  if (responderPlayerId !== expectedResponder) {
    throw new EngineError(
      'NOT_YOUR_TURN',
      'Only the current attack responder may act',
    );
  }

  if (response.kind === 'pass') {
    if (pending.stepInIndex === -1) {
      const attackDesignId = getCardDesignId(pending.attackCardInstanceId);
      const target = state.players[pending.targetPlayerId];
      const discardCardInstanceId = response.discardCardInstanceId;
      if (attackDesignId !== 'card_02' && discardCardInstanceId !== undefined) {
        throw new EngineError(
          'INVALID_DISCARD',
          'Only Double Down allows the target to select a discard',
        );
      }

      if (
        attackDesignId === 'card_02' &&
        target.hand.length > 0 &&
        discardCardInstanceId === undefined
      ) {
        throw new EngineError(
          'INVALID_DISCARD',
          'The target must select a card for Double Down if damage succeeds',
        );
      }

      if (
        discardCardInstanceId !== undefined &&
        !target.hand.includes(discardCardInstanceId)
      ) {
        throw new EngineError(
          'INVALID_DISCARD',
          'The selected Double Down card must be in the target hand',
        );
      }

      const stateWithDiscardChoice = matchStateSchema.parse({
        ...state,
        pendingAttack: {
          ...pending,
          targetDiscardCardInstanceId: discardCardInstanceId ?? null,
        },
      });
      if (pending.stepInPlayerIds.length === 0) {
        return resolveDamage(stateWithDiscardChoice, nowMs);
      }

      return matchStateSchema.parse({
        ...stateWithDiscardChoice,
        version: state.version + 1,
        pendingAttack: {
          ...stateWithDiscardChoice.pendingAttack,
          stepInIndex: 0,
        },
      });
    }

    if (response.discardCardInstanceId !== undefined) {
      throw new EngineError(
        'INVALID_DISCARD',
        'Only the attack target may select a Double Down discard',
      );
    }

    const nextStepInIndex = pending.stepInIndex + 1;
    if (nextStepInIndex >= pending.stepInPlayerIds.length) {
      return resolveDamage(state, nowMs);
    }

    return matchStateSchema.parse({
      ...state,
      version: state.version + 1,
      pendingAttack: { ...pending, stepInIndex: nextStepInIndex },
    });
  }

  if (pending.stepInIndex === -1) {
    if (response.kind !== 'defend') {
      throw new EngineError(
        'INVALID_REACTION',
        'The attack target may defend or pass; Step In follows a pass',
      );
    }

    return resolveDefense(state, responderPlayerId, response.cardInstanceId);
  }

  if (response.kind !== 'step_in') {
    throw new EngineError(
      'INVALID_REACTION',
      'Only Step In may be played after the target passes',
    );
  }

  return resolveStepIn(state, responderPlayerId, response.cardInstanceId);
}

export function playSafePlace(
  state: MatchState,
  casterPlayerId: string,
  targetPlayerId: string,
  cardInstanceId: string,
): MatchState {
  if (state.phase !== 'active_turn') {
    throw new EngineError(
      'INVALID_PHASE',
      'Safe Place can only be played during the active_turn phase',
    );
  }

  if (state.currentPlayerId !== casterPlayerId) {
    throw new EngineError(
      'NOT_YOUR_TURN',
      'Only the current player may play Safe Place',
    );
  }

  const caster = state.players[casterPlayerId];
  if (!caster || caster.status !== 'active' || caster.hearts < 1) {
    throw new EngineError(
      'NOT_ELIGIBLE',
      'Safe Place requires an Active player',
    );
  }

  const target = state.players[targetPlayerId];
  if (!target || target.status !== 'active' || target.hearts < 1) {
    throw new EngineError(
      'INVALID_TARGET',
      'Safe Place must target an Active player',
    );
  }

  requireCardInHand(
    state,
    casterPlayerId,
    cardInstanceId,
    new Set([safePlaceCardId]),
  );
  if (
    state.activeEffects.some(
      (effect) =>
        effect.type === 'safe_place' &&
        effect.targetPlayerId === targetPlayerId,
    )
  ) {
    throw new EngineError(
      'SAFE_PLACE_ALREADY_ACTIVE',
      'The target already has a Safe Place shield',
    );
  }

  const played = playActionCard(
    state,
    casterPlayerId,
    cardInstanceId,
    new Set([safePlaceCardId]),
  );
  return matchStateSchema.parse({
    ...played.state,
    version: state.version + 1,
    players: {
      ...played.state.players,
    },
    activeEffects: [
      ...played.state.activeEffects,
      {
        type: 'safe_place',
        casterPlayerId,
        targetPlayerId,
      },
    ],
  });
}
