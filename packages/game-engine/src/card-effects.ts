import { playActionCard } from './action-card.js';
import { drawCardsFromPiles } from './deck.js';
import { EngineError } from './errors.js';
import { nextRandomIndex, type RandomSource } from './random.js';
import { matchStateSchema, type MatchState } from './state.js';
import { MAX_SUSPICION, recordNoisyManipulation } from './suspicion.js';

const pointFingersCardIds = new Set(['card_13']);
const cleanSlateCardIds = new Set(['card_14']);
const stirThePotCardIds = new Set(['card_15']);
const cardSwapCardIds = new Set(['card_16']);
const firstAidCardIds = new Set(['card_17']);
const catchYourBreathCardIds = new Set(['card_18']);
const patchUpCardIds = new Set(['card_20']);
const spotlightCardIds = new Set(['card_23']);

function requireSurvivingTarget(
  state: MatchState,
  actorPlayerId: string,
  targetPlayerId: string,
): void {
  const target = state.players[targetPlayerId];
  if (
    !target ||
    targetPlayerId === actorPlayerId ||
    target.status === 'eliminated'
  ) {
    throw new EngineError(
      'INVALID_TARGET',
      'The selected target must be another surviving player',
    );
  }
}

function finishNoisyManipulation(
  state: MatchState,
  actorPlayerId: string,
): MatchState {
  const noisyState = recordNoisyManipulation(state, actorPlayerId);
  return matchStateSchema.parse({ ...noisyState, version: state.version });
}

export function playPointFingers(
  state: MatchState,
  actorPlayerId: string,
  targetPlayerId: string,
  cardInstanceId: string,
): MatchState {
  requireSurvivingTarget(state, actorPlayerId, targetPlayerId);
  const played = playActionCard(
    state,
    actorPlayerId,
    cardInstanceId,
    pointFingersCardIds,
  );
  const target = played.state.players[targetPlayerId];
  const targetedState = matchStateSchema.parse({
    ...played.state,
    players: {
      ...played.state.players,
      [targetPlayerId]: {
        ...target,
        suspicion: Math.min(MAX_SUSPICION, target.suspicion + 1),
      },
    },
  });

  return finishNoisyManipulation(targetedState, actorPlayerId);
}

export function playCleanSlate(
  state: MatchState,
  actorPlayerId: string,
  cardInstanceId: string,
): MatchState {
  const played = playActionCard(
    state,
    actorPlayerId,
    cardInstanceId,
    cleanSlateCardIds,
  );
  const actor = played.state.players[actorPlayerId];
  const reducedState = matchStateSchema.parse({
    ...played.state,
    players: {
      ...played.state.players,
      [actorPlayerId]: {
        ...actor,
        suspicion: Math.max(0, actor.suspicion - 2),
      },
    },
  });

  return finishNoisyManipulation(reducedState, actorPlayerId);
}

export function playStirThePot(
  state: MatchState,
  actorPlayerId: string,
  targetPlayerIds: string[],
  cardInstanceId: string,
): MatchState {
  if (targetPlayerIds.length !== 2 || new Set(targetPlayerIds).size !== 2) {
    throw new EngineError(
      'INVALID_TARGET',
      'Stir the Pot requires two different other Active players with cards',
    );
  }

  for (const targetPlayerId of targetPlayerIds) {
    const target = state.players[targetPlayerId];
    if (
      !target ||
      targetPlayerId === actorPlayerId ||
      target.status !== 'active' ||
      target.hearts < 1 ||
      target.hand.length === 0
    ) {
      throw new EngineError(
        'INVALID_TARGET',
        'Stir the Pot requires two different other Active players with cards',
      );
    }
  }

  const actorSeatIndex = state.seatOrder.indexOf(actorPlayerId);
  if (actorSeatIndex < 0) {
    throw new EngineError(
      'INVALID_PLAYER',
      'The current player must have a seat to play Stir the Pot',
    );
  }
  const orderedTargetIds = [...targetPlayerIds].sort(
    (left, right) =>
      ((state.seatOrder.indexOf(left) -
        actorSeatIndex +
        state.seatOrder.length) %
        state.seatOrder.length) -
      ((state.seatOrder.indexOf(right) -
        actorSeatIndex +
        state.seatOrder.length) %
        state.seatOrder.length),
  );
  const firstTargetPlayerId = orderedTargetIds[0];
  const secondTargetPlayerId = orderedTargetIds[1];
  if (!firstTargetPlayerId || !secondTargetPlayerId) {
    throw new EngineError(
      'INVALID_TARGET',
      'Stir the Pot requires two targets',
    );
  }

  const played = playActionCard(
    state,
    actorPlayerId,
    cardInstanceId,
    stirThePotCardIds,
  );
  const noisyState = finishNoisyManipulation(played.state, actorPlayerId);
  return matchStateSchema.parse({
    ...noisyState,
    phase: 'awaiting_card_effect',
    pendingCardEffect: {
      kind: 'stir_the_pot_discards',
      actorPlayerId,
      targetPlayerIds: [firstTargetPlayerId, secondTargetPlayerId],
      responseIndex: 0,
    },
  });
}

export interface CardEffectDiscardOutcome {
  state: MatchState;
  nextResponderPlayerId: string | null;
}

export function currentCardEffectResponder(state: MatchState): string | null {
  if (state.phase !== 'awaiting_card_effect' || !state.pendingCardEffect) {
    return null;
  }

  if (state.pendingCardEffect.kind === 'catch_your_breath_discard') {
    return state.pendingCardEffect.actorPlayerId;
  }

  return (
    state.pendingCardEffect.targetPlayerIds[
      state.pendingCardEffect.responseIndex
    ] ?? null
  );
}

export function respondToCardEffectDiscard(
  state: MatchState,
  responderPlayerId: string,
  cardInstanceId: string,
): CardEffectDiscardOutcome {
  if (state.phase !== 'awaiting_card_effect' || !state.pendingCardEffect) {
    throw new EngineError(
      'INVALID_PHASE',
      'A card-effect discard requires a pending card effect',
    );
  }

  if (currentCardEffectResponder(state) !== responderPlayerId) {
    throw new EngineError(
      'NOT_YOUR_TURN',
      'Only the current card-effect responder may discard',
    );
  }

  const responder = state.players[responderPlayerId];
  if (!responder?.hand.includes(cardInstanceId)) {
    throw new EngineError(
      'INVALID_DISCARD',
      'The selected card must be in the responder hand',
    );
  }

  const players = {
    ...state.players,
    [responderPlayerId]: {
      ...responder,
      hand: responder.hand.filter((card) => card !== cardInstanceId),
    },
  };
  const discardPile = [...state.discardPile, cardInstanceId];

  if (
    state.pendingCardEffect.kind === 'catch_your_breath_discard' ||
    state.pendingCardEffect.responseIndex === 1
  ) {
    const completed = matchStateSchema.parse({
      ...state,
      version: state.version + 1,
      phase: 'active_turn',
      pendingCardEffect: null,
      players,
      discardPile,
    });
    return { state: completed, nextResponderPlayerId: null };
  }

  const nextState = matchStateSchema.parse({
    ...state,
    version: state.version + 1,
    pendingCardEffect: {
      ...state.pendingCardEffect,
      responseIndex: 1,
    },
    players,
    discardPile,
  });
  return {
    state: nextState,
    nextResponderPlayerId: currentCardEffectResponder(nextState),
  };
}

export interface CardSwapOutcome {
  state: MatchState;
  privateResult: {
    givenToTargetCardInstanceId: string;
    receivedCardInstanceId: string;
  };
}

export function playCardSwap(
  state: MatchState,
  actorPlayerId: string,
  targetPlayerId: string,
  cardInstanceId: string,
  random: RandomSource,
): CardSwapOutcome {
  requireSurvivingTarget(state, actorPlayerId, targetPlayerId);
  if (state.players[targetPlayerId].hand.length === 0) {
    throw new EngineError(
      'INVALID_TARGET',
      'Card Swap requires the target to have a card',
    );
  }

  const played = playActionCard(
    state,
    actorPlayerId,
    cardInstanceId,
    cardSwapCardIds,
  );
  const actor = played.state.players[actorPlayerId];
  if (actor.hand.length === 0) {
    throw new EngineError(
      'INVALID_CARD',
      'Card Swap requires the current player to have another card',
    );
  }

  const target = played.state.players[targetPlayerId];
  const givenToTargetCardInstanceId =
    actor.hand[nextRandomIndex(actor.hand.length, random)];
  const receivedCardInstanceId =
    target.hand[nextRandomIndex(target.hand.length, random)];
  if (
    givenToTargetCardInstanceId === undefined ||
    receivedCardInstanceId === undefined
  ) {
    throw new EngineError('INVALID_CARD', 'Card Swap could not select cards');
  }

  const swappedState = matchStateSchema.parse({
    ...played.state,
    players: {
      ...played.state.players,
      [actorPlayerId]: {
        ...actor,
        hand: [
          ...actor.hand.filter((card) => card !== givenToTargetCardInstanceId),
          receivedCardInstanceId,
        ],
      },
      [targetPlayerId]: {
        ...target,
        hand: [
          ...target.hand.filter((card) => card !== receivedCardInstanceId),
          givenToTargetCardInstanceId,
        ],
      },
    },
  });

  return {
    state: swappedState,
    privateResult: {
      givenToTargetCardInstanceId,
      receivedCardInstanceId,
    },
  };
}

export function playFirstAid(
  state: MatchState,
  actorPlayerId: string,
  targetPlayerId: string,
  cardInstanceId: string,
): MatchState {
  const target = state.players[targetPlayerId];
  if (!target || target.status === 'eliminated') {
    throw new EngineError(
      'INVALID_TARGET',
      'First Aid must target a surviving player',
    );
  }

  const played = playActionCard(
    state,
    actorPlayerId,
    cardInstanceId,
    firstAidCardIds,
  );
  const targetAfterPlay = played.state.players[targetPlayerId];
  return matchStateSchema.parse({
    ...played.state,
    players: {
      ...played.state.players,
      [targetPlayerId]: {
        ...targetAfterPlay,
        hearts: Math.min(3, targetAfterPlay.hearts + 1),
        status:
          targetAfterPlay.status === 'cornered'
            ? 'active'
            : targetAfterPlay.status,
      },
    },
  });
}

export interface CatchYourBreathOutcome {
  state: MatchState;
  privateResult: { drawnCardInstanceIds: string[] };
}

export function playCatchYourBreath(
  state: MatchState,
  actorPlayerId: string,
  cardInstanceId: string,
  random: RandomSource,
): CatchYourBreathOutcome {
  const played = playActionCard(
    state,
    actorPlayerId,
    cardInstanceId,
    catchYourBreathCardIds,
  );
  const draw = drawCardsFromPiles(
    played.state.drawPile,
    played.state.discardPile,
    2,
    random,
  );
  const actor = played.state.players[actorPlayerId];
  const nextState = matchStateSchema.parse({
    ...played.state,
    phase: 'awaiting_card_effect',
    pendingCardEffect: {
      kind: 'catch_your_breath_discard',
      actorPlayerId,
    },
    players: {
      ...played.state.players,
      [actorPlayerId]: {
        ...actor,
        hand: [...actor.hand, ...draw.cards],
      },
    },
    drawPile: draw.drawPile,
    discardPile: draw.discardPile,
  });

  return {
    state: nextState,
    privateResult: { drawnCardInstanceIds: draw.cards },
  };
}

export function playPatchUp(
  state: MatchState,
  actorPlayerId: string,
  cardInstanceId: string,
): MatchState {
  const played = playActionCard(
    state,
    actorPlayerId,
    cardInstanceId,
    patchUpCardIds,
  );
  const actor = played.state.players[actorPlayerId];
  return matchStateSchema.parse({
    ...played.state,
    players: {
      ...played.state.players,
      [actorPlayerId]: {
        ...actor,
        hearts: Math.min(3, actor.hearts + 1),
        suspicion: Math.max(0, actor.suspicion - 1),
      },
    },
  });
}

export interface SpotlightOutcome {
  state: MatchState;
  publicResult: { suspicionByPlayerId: Record<string, number> };
  privateResult: { drawnCardInstanceId: string | null };
}

export function playSpotlight(
  state: MatchState,
  actorPlayerId: string,
  cardInstanceId: string,
  random: RandomSource,
): SpotlightOutcome {
  const played = playActionCard(
    state,
    actorPlayerId,
    cardInstanceId,
    spotlightCardIds,
  );
  const draw = drawCardsFromPiles(
    played.state.drawPile,
    played.state.discardPile,
    1,
    random,
  );
  const actor = played.state.players[actorPlayerId];
  const players = {
    ...played.state.players,
    [actorPlayerId]: {
      ...actor,
      hand: [...actor.hand, ...draw.cards],
    },
  };

  return {
    state: matchStateSchema.parse({
      ...played.state,
      players,
      drawPile: draw.drawPile,
      discardPile: draw.discardPile,
    }),
    publicResult: {
      suspicionByPlayerId: Object.fromEntries(
        Object.entries(played.state.players).map(([playerId, player]) => [
          playerId,
          player.suspicion,
        ]),
      ),
    },
    privateResult: { drawnCardInstanceId: draw.cards[0] ?? null },
  };
}
