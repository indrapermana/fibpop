import { drawCardsFromPiles } from './deck.js';
import { EngineError } from './errors.js';
import { nextRandomIndex, type RandomSource } from './random.js';
import { matchStateSchema, type MatchState } from './state.js';
import { hasBehaviorEvidenceQualifyingAction } from './suspicion.js';
import { spendAction } from './turns.js';

export type EvidenceKind = 'clue' | 'behavior';

export type InvestigationCardId =
  'card_09' | 'card_10' | 'card_11' | 'card_12' | 'card_22';

export type InvestigationDefense =
  | { kind: 'discard'; cardInstanceId: string }
  | { kind: 'misdirection'; cardInstanceId: string };

export interface BasicObserveOutcome {
  state: MatchState;
  evidenceAdded: boolean;
}

export interface InvestigationOutcome {
  state: MatchState;
  actionCost: 0 | 1;
  evidenceAdded: boolean;
  privateResult: {
    inspectedCardInstanceId: string | null;
    drawnCardInstanceId: string | null;
    revealedActionCardInstanceId: string | null;
  };
}

export interface PlayInvestigationInput {
  actorPlayerId: string;
  targetPlayerId: string;
  cardInstanceId: string;
  random: RandomSource;
  defense?: InvestigationDefense;
}

const investigationCardIds = new Set<string>([
  'card_09',
  'card_10',
  'card_11',
  'card_12',
]);
const playableInvestigationCardIds = new Set<string>([
  ...investigationCardIds,
  'card_22',
]);

function cardDesignId(cardInstanceId: string): string | null {
  return /^(card_\d{2}):[1-9]\d*$/.exec(cardInstanceId)?.[1] ?? null;
}

function requireActiveTurnActor(
  state: MatchState,
  actorPlayerId: string,
): void {
  if (state.phase !== 'active_turn') {
    throw new EngineError(
      'INVALID_PHASE',
      'An investigation requires the active_turn phase',
    );
  }

  if (state.currentPlayerId !== actorPlayerId) {
    throw new EngineError(
      'NOT_YOUR_TURN',
      'Only the current player may investigate',
    );
  }

  const actor = state.players[actorPlayerId];
  if (!actor || actor.status !== 'active' || actor.hearts < 1) {
    throw new EngineError(
      'NOT_ELIGIBLE',
      'An investigation requires an Active player',
    );
  }
}

function requireTarget(state: MatchState, targetPlayerId: string) {
  const target = state.players[targetPlayerId];
  if (!target) {
    throw new EngineError(
      'INVALID_TARGET',
      `Unknown investigation target: ${targetPlayerId}`,
    );
  }

  return target;
}

function hasEvidence(
  state: MatchState,
  investigatorPlayerId: string,
  suspectPlayerId: string,
  kind: EvidenceKind,
): boolean {
  return (
    state.players[investigatorPlayerId]?.evidence[suspectPlayerId]?.[kind] ??
    false
  );
}

export function grantEvidence(
  state: MatchState,
  investigatorPlayerId: string,
  suspectPlayerId: string,
  kind: EvidenceKind,
): MatchState {
  const investigator = state.players[investigatorPlayerId];
  if (!investigator) {
    throw new EngineError(
      'INVALID_PLAYER',
      `Unknown investigator: ${investigatorPlayerId}`,
    );
  }

  if (!state.players[suspectPlayerId]) {
    throw new EngineError(
      'INVALID_TARGET',
      `Unknown Evidence target: ${suspectPlayerId}`,
    );
  }

  if (hasEvidence(state, investigatorPlayerId, suspectPlayerId, kind)) {
    return state;
  }

  const evidence = investigator.evidence[suspectPlayerId] ?? {
    clue: false,
    behavior: false,
  };

  return matchStateSchema.parse({
    ...state,
    version: state.version + 1,
    players: {
      ...state.players,
      [investigatorPlayerId]: {
        ...investigator,
        evidence: {
          ...investigator.evidence,
          [suspectPlayerId]: { ...evidence, [kind]: true },
        },
      },
    },
  });
}

export function basicObserve(
  state: MatchState,
  actorPlayerId: string,
  targetPlayerId: string,
): BasicObserveOutcome {
  requireActiveTurnActor(state, actorPlayerId);
  requireTarget(state, targetPlayerId);

  const qualifies = hasBehaviorEvidenceQualifyingAction(state, targetPlayerId);
  const spent = spendAction(state, 'action');
  const stateWithEvidence = qualifies
    ? grantEvidence(spent, actorPlayerId, targetPlayerId, 'behavior')
    : spent;
  const evidenceAdded =
    qualifies && !hasEvidence(state, actorPlayerId, targetPlayerId, 'behavior');

  return {
    state: matchStateSchema.parse({
      ...stateWithEvidence,
      version: state.version + 1,
    }),
    evidenceAdded,
  };
}

export function playInvestigation(
  state: MatchState,
  input: PlayInvestigationInput,
): InvestigationOutcome {
  requireActiveTurnActor(state, input.actorPlayerId);
  const target = requireTarget(state, input.targetPlayerId);
  const actor = state.players[input.actorPlayerId];
  const cardId = cardDesignId(input.cardInstanceId);

  if (cardId === null || !playableInvestigationCardIds.has(cardId)) {
    throw new EngineError(
      'INVALID_CARD',
      'The selected card is not a supported Investigation or Extra Clue',
    );
  }

  if (!actor.hand.includes(input.cardInstanceId)) {
    throw new EngineError(
      'INVALID_CARD',
      'The Investigation card must be in the current player hand',
    );
  }

  if (cardId === 'card_11' && input.targetPlayerId === input.actorPlayerId) {
    throw new EngineError('INVALID_TARGET', 'Peek must target another player');
  }

  const inspectsHand =
    cardId === 'card_10' || cardId === 'card_11' || cardId === 'card_22';
  if (input.defense && !inspectsHand) {
    throw new EngineError(
      'INVALID_INSPECTION_DEFENSE',
      'This Investigation does not inspect a hand',
    );
  }

  const targetHandAfterPlay =
    input.targetPlayerId === input.actorPlayerId
      ? target.hand.filter((card) => card !== input.cardInstanceId)
      : target.hand;
  let defendedCardInstanceId: string | null = null;
  if (input.defense) {
    defendedCardInstanceId = input.defense.cardInstanceId;
    if (!targetHandAfterPlay.includes(defendedCardInstanceId)) {
      throw new EngineError(
        'INVALID_INSPECTION_DEFENSE',
        'The defense card must be in the target player hand',
      );
    }

    if (
      input.defense.kind === 'misdirection' &&
      (input.targetPlayerId === input.actorPlayerId ||
        cardDesignId(defendedCardInstanceId) !== 'card_24')
    ) {
      throw new EngineError(
        'INVALID_INSPECTION_DEFENSE',
        'Misdirection must be played by the other target from their hand',
      );
    }

    if (input.defense.kind === 'discard' && cardId !== 'card_22') {
      throw new EngineError(
        'INVALID_INSPECTION_DEFENSE',
        'Only the Extra Clue target may discard to prevent inspection',
      );
    }
  }

  const isInvestigationCard = investigationCardIds.has(cardId);
  const firstInvestigationAgainstTarget =
    isInvestigationCard &&
    !state.investigationTargetsThisTurn.includes(input.targetPlayerId);
  const actionCost: 0 | 1 =
    firstInvestigationAgainstTarget && target.suspicion === 3 ? 0 : 1;
  const spent = spendAction(state, 'action', actionCost);
  const players = { ...spent.players };
  const actorAfterPlay = {
    ...players[input.actorPlayerId],
    hand: actor.hand.filter((card) => card !== input.cardInstanceId),
    lastPlayedActionCardInstanceId: input.cardInstanceId,
  };
  players[input.actorPlayerId] = actorAfterPlay;

  if (input.defense && defendedCardInstanceId !== null) {
    const defendingPlayer = players[input.targetPlayerId];
    players[input.targetPlayerId] = {
      ...defendingPlayer,
      hand: defendingPlayer.hand.filter(
        (card) => card !== defendedCardInstanceId,
      ),
    };
  }

  const discardPile = [
    ...spent.discardPile,
    input.cardInstanceId,
    ...(defendedCardInstanceId === null ? [] : [defendedCardInstanceId]),
  ];
  const investigationTargetsThisTurn = isInvestigationCard
    ? state.investigationTargetsThisTurn.includes(input.targetPlayerId)
      ? state.investigationTargetsThisTurn
      : [...state.investigationTargetsThisTurn, input.targetPlayerId]
    : state.investigationTargetsThisTurn;

  let inspectedCardInstanceId: string | null = null;
  if (inspectsHand && !input.defense && targetHandAfterPlay.length > 0) {
    inspectedCardInstanceId =
      targetHandAfterPlay[
        nextRandomIndex(targetHandAfterPlay.length, input.random)
      ];
  }

  let drawnCardInstanceId: string | null = null;
  let drawPile = [...spent.drawPile];
  let nextDiscardPile = discardPile;
  if (cardId === 'card_11') {
    const draw = drawCardsFromPiles(drawPile, nextDiscardPile, 1, input.random);
    drawnCardInstanceId = draw.cards[0] ?? null;
    drawPile = draw.drawPile;
    nextDiscardPile = draw.discardPile;
    if (drawnCardInstanceId !== null) {
      players[input.actorPlayerId] = {
        ...players[input.actorPlayerId],
        hand: [...players[input.actorPlayerId].hand, drawnCardInstanceId],
      };
    }
  }

  let evidenceKind: EvidenceKind | null = null;
  if (cardId === 'card_10' || cardId === 'card_12' || cardId === 'card_22') {
    evidenceKind = 'clue';
  } else if (
    cardId === 'card_09' &&
    hasBehaviorEvidenceQualifyingAction(state, input.targetPlayerId)
  ) {
    evidenceKind = 'behavior';
  }

  const evidenceAdded =
    evidenceKind !== null &&
    !hasEvidence(
      state,
      input.actorPlayerId,
      input.targetPlayerId,
      evidenceKind,
    );
  const stateWithEffects = matchStateSchema.parse({
    ...spent,
    version: state.version + 1,
    players,
    drawPile,
    discardPile: nextDiscardPile,
    investigationTargetsThisTurn,
  });
  const finalState =
    evidenceKind === null
      ? stateWithEffects
      : grantEvidence(
          stateWithEffects,
          input.actorPlayerId,
          input.targetPlayerId,
          evidenceKind,
        );
  const revealedActionCardInstanceId =
    cardId === 'card_12'
      ? players[input.targetPlayerId].lastPlayedActionCardInstanceId
      : null;

  return {
    state: matchStateSchema.parse({
      ...finalState,
      version: state.version + 1,
    }),
    actionCost,
    evidenceAdded,
    privateResult: {
      inspectedCardInstanceId,
      drawnCardInstanceId,
      revealedActionCardInstanceId,
    },
  };
}
