import { getCardDesignId } from './card-instance.js';
import { EngineError } from './errors.js';
import { matchStateSchema, type MatchState } from './state.js';
import { spendAction, type TurnActionKind } from './turns.js';

export interface PlayedActionCard {
  state: MatchState;
  cardDesignId: string;
}

export function playActionCard(
  state: MatchState,
  actorPlayerId: string,
  cardInstanceId: string,
  allowedCardDesignIds: ReadonlySet<string>,
  kind: TurnActionKind = 'action',
  cost: 0 | 1 = 1,
): PlayedActionCard {
  if (state.phase !== 'active_turn') {
    throw new EngineError(
      'INVALID_PHASE',
      'An Action card can only be played during the active_turn phase',
    );
  }

  if (state.currentPlayerId !== actorPlayerId) {
    throw new EngineError(
      'NOT_YOUR_TURN',
      'Only the current player may play an Action card',
    );
  }

  const actor = state.players[actorPlayerId];
  if (!actor || actor.status !== 'active' || actor.hearts < 1) {
    throw new EngineError(
      'NOT_ELIGIBLE',
      'An Action card requires an Active player',
    );
  }

  const cardDesignId = getCardDesignId(cardInstanceId);
  if (
    cardDesignId === null ||
    !allowedCardDesignIds.has(cardDesignId) ||
    !actor.hand.includes(cardInstanceId)
  ) {
    throw new EngineError(
      'INVALID_CARD',
      'The selected Action card must be in the player hand',
    );
  }

  const spent = spendAction(state, kind, cost);
  const players = {
    ...spent.players,
    [actorPlayerId]: {
      ...actor,
      hand: actor.hand.filter((card) => card !== cardInstanceId),
      lastPlayedActionCardInstanceId: cardInstanceId,
    },
  };

  return {
    state: matchStateSchema.parse({
      ...spent,
      players,
      discardPile: [...state.discardPile, cardInstanceId],
    }),
    cardDesignId,
  };
}
