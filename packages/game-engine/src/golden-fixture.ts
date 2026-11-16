import { z } from 'zod';

import { matchStateSchema, RULES_VERSION } from './state.js';

export const goldenFixtureSchema = z
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

export type GoldenFixture = z.infer<typeof goldenFixtureSchema>;
