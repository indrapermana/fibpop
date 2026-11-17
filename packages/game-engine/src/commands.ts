import { z } from 'zod';

import { EngineError, failed, type EngineResult } from './errors.js';
import type { MatchState } from './state.js';
import { endTurn, spendAction } from './turns.js';

export const turnCommandSchema = z.discriminatedUnion('type', [
  z
    .object({
      type: z.literal('END_TURN'),
      payload: z
        .object({
          discardCardInstanceIds: z.array(z.string().min(1)),
        })
        .strict(),
    })
    .strict(),
  z
    .object({
      type: z.literal('SPEND_ACTION'),
      payload: z
        .object({
          kind: z.enum(['attack', 'action']),
          cost: z.union([z.literal(0), z.literal(1)]).optional(),
        })
        .strict(),
    })
    .strict(),
]);

export type TurnCommand = z.infer<typeof turnCommandSchema>;

export function executeTurnCommand(
  state: MatchState,
  actorPlayerId: string,
  input: unknown,
): EngineResult<MatchState> {
  const parsed = turnCommandSchema.safeParse(input);
  if (!parsed.success) {
    return failed('INVALID_COMMAND', 'Turn command payload is invalid.');
  }

  if (state.phase !== 'active_turn') {
    return failed(
      'INVALID_PHASE',
      'Turn commands require the active_turn phase.',
    );
  }

  if (state.currentPlayerId !== actorPlayerId) {
    return failed(
      'NOT_YOUR_TURN',
      'Only the current player may submit this command.',
    );
  }

  const actor = state.players[actorPlayerId];
  if (!actor || actor.status !== 'active') {
    return failed('NOT_ELIGIBLE', 'The current player is not Active.');
  }

  try {
    if (parsed.data.type === 'END_TURN') {
      return {
        ok: true,
        value: endTurn(state, parsed.data.payload.discardCardInstanceIds),
      };
    }

    return {
      ok: true,
      value: spendAction(
        state,
        parsed.data.payload.kind,
        parsed.data.payload.cost,
      ),
    };
  } catch (error) {
    if (error instanceof EngineError) {
      return failed(error.code, error.message);
    }

    throw error;
  }
}

export function validateAttackTarget(
  state: MatchState,
  actorPlayerId: string,
  targetPlayerId: string,
): EngineResult<{ targetPlayerId: string }> {
  if (state.phase !== 'active_turn') {
    return failed('INVALID_PHASE', 'Attacks require the active_turn phase.');
  }

  if (state.currentPlayerId !== actorPlayerId) {
    return failed('NOT_YOUR_TURN', 'Only the current player may attack.');
  }

  const actor = state.players[actorPlayerId];
  if (!actor || actor.status !== 'active' || actor.hearts < 1) {
    return failed('NOT_ELIGIBLE', 'The attacker must be Active.');
  }

  if (state.actionsRemaining < 1) {
    return failed('NO_ACTIONS_REMAIN', 'No actions remain this turn.');
  }

  if (state.attacksUsedThisTurn >= 1) {
    return failed('ATTACK_LIMIT', 'Only one attack is allowed per turn.');
  }

  const target = state.players[targetPlayerId];
  if (
    targetPlayerId === actorPlayerId ||
    !target ||
    target.status !== 'active' ||
    target.hearts < 1
  ) {
    return failed(
      'INVALID_TARGET',
      'Attack target must be another Active player.',
    );
  }

  return { ok: true, value: { targetPlayerId } };
}
