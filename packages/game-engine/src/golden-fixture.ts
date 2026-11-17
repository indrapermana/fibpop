import { z } from 'zod';

import { matchStateSchema, RULES_VERSION } from './state.js';

const stateTransitionFixtureSchema = z
  .object({
    fixtureVersion: z.literal(1),
    rulesVersion: z.literal(RULES_VERSION),
    catalogVersion: z.string().regex(/^\d+\.\d+\.\d+$/),
    name: z.string().regex(/^[a-z0-9-]+$/),
    initialState: matchStateSchema,
    commands: z.array(z.unknown()),
    expectedPublicDelta: z.array(z.unknown()),
    expectedPrivateDelta: z.record(z.string(), z.unknown()),
  })
  .strict();

export const matchSetupFixtureSchema = z
  .object({
    fixtureVersion: z.literal(1),
    rulesVersion: z.literal(RULES_VERSION),
    catalogVersion: z.string().regex(/^\d+\.\d+\.\d+$/),
    name: z.string().regex(/^[a-z0-9-]+$/),
    setup: z
      .object({
        matchId: z.string().min(1),
        playerIds: z.array(z.string().min(1)).min(4).max(8),
        randomSequence: z.array(z.number().min(0).lt(1)).min(1),
      })
      .strict(),
    expectedState: matchStateSchema,
  })
  .strict();

export const turnStartFixtureSchema = z
  .object({
    fixtureVersion: z.literal(1),
    rulesVersion: z.literal(RULES_VERSION),
    catalogVersion: z.string().regex(/^\d+\.\d+\.\d+$/),
    name: z.string().regex(/^[a-z0-9-]+$/),
    initialState: matchStateSchema,
    randomSequence: z.array(z.number().min(0).lt(1)).min(1),
    expectedState: matchStateSchema,
  })
  .strict();

export const endTurnFixtureSchema = z
  .object({
    fixtureVersion: z.literal(1),
    rulesVersion: z.literal(RULES_VERSION),
    catalogVersion: z.string().regex(/^\d+\.\d+\.\d+$/),
    name: z.string().regex(/^[a-z0-9-]+$/),
    initialState: matchStateSchema,
    discardCardInstanceIds: z.array(z.string()),
    expectedState: matchStateSchema,
  })
  .strict();

export const goldenFixtureSchema = z.union([
  stateTransitionFixtureSchema,
  matchSetupFixtureSchema,
  turnStartFixtureSchema,
  endTurnFixtureSchema,
]);

export type GoldenFixture = z.infer<typeof goldenFixtureSchema>;
