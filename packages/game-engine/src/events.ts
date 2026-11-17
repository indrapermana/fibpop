import { z } from 'zod';

import { EngineError } from './errors.js';
import { matchStateSchema, type MatchState } from './state.js';

const changesSchema = matchStateSchema
  .omit({
    matchId: true,
    rulesVersion: true,
    catalogVersion: true,
    version: true,
  })
  .partial();

export const stateTransitionEventSchema = z
  .object({
    type: z.literal('STATE_TRANSITION'),
    matchId: z.string().min(1),
    previousVersion: z.number().int().nonnegative(),
    version: z.number().int().positive(),
    changes: changesSchema,
  })
  .strict()
  .refine((event) => event.version === event.previousVersion + 1, {
    message: 'A transition must advance exactly one version',
  });

export type StateTransitionEvent = z.infer<typeof stateTransitionEventSchema>;

export function recordTransition(
  previous: MatchState,
  next: MatchState,
): StateTransitionEvent {
  const before = matchStateSchema.parse(previous);
  const after = matchStateSchema.parse(next);
  if (
    before.matchId !== after.matchId ||
    before.rulesVersion !== after.rulesVersion ||
    before.catalogVersion !== after.catalogVersion ||
    after.version !== before.version + 1
  ) {
    throw new EngineError(
      'INVALID_EVENT',
      'Transition identity or version does not match',
    );
  }

  const stateFields = (state: MatchState) =>
    changesSchema.parse(
      Object.fromEntries(
        Object.entries(state).filter(([key]) =>
          Object.hasOwn(changesSchema.shape, key),
        ),
      ),
    );
  const beforeFields = stateFields(before);
  const afterFields = stateFields(after);
  const changes = Object.fromEntries(
    Object.entries(afterFields).filter(
      ([key, value]) =>
        JSON.stringify(value) !==
        JSON.stringify(beforeFields[key as keyof typeof beforeFields]),
    ),
  );
  return stateTransitionEventSchema.parse({
    type: 'STATE_TRANSITION',
    matchId: before.matchId,
    previousVersion: before.version,
    version: after.version,
    changes,
  });
}

export function applyTransition(state: MatchState, input: unknown): MatchState {
  const event = stateTransitionEventSchema.safeParse(input);
  if (!event.success) {
    throw new EngineError('INVALID_EVENT', 'Invalid state transition event');
  }
  if (
    state.matchId !== event.data.matchId ||
    state.version !== event.data.previousVersion
  ) {
    throw new EngineError(
      'INVALID_EVENT',
      'State transition is stale or belongs to another match',
    );
  }
  return matchStateSchema.parse({
    ...state,
    ...event.data.changes,
    version: event.data.version,
  });
}

export function replayTransitions(
  initialState: MatchState,
  events: readonly unknown[],
): MatchState {
  return events.reduce<MatchState>(
    (state, event) => applyTransition(state, event),
    matchStateSchema.parse(initialState),
  );
}
