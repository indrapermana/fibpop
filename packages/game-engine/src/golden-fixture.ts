import { z } from 'zod';

import { engineErrorCodes } from './errors.js';
import { matchStateSchema, RULES_VERSION, CATALOG_VERSION } from './state.js';

const id = z.string().min(1);
const randomSequence = z.array(z.number().finite().min(0).lt(1));
const timed = z.number().int().nonnegative();
const reactionSchema = z.discriminatedUnion('kind', [
  z
    .object({ kind: z.literal('pass'), discardCardInstanceId: id.optional() })
    .strict(),
  z.object({ kind: z.literal('defend'), cardInstanceId: id }).strict(),
  z.object({ kind: z.literal('step_in'), cardInstanceId: id }).strict(),
]);
const defenseSchema = z.discriminatedUnion('kind', [
  z.object({ kind: z.literal('discard'), cardInstanceId: id }).strict(),
  z.object({ kind: z.literal('misdirection'), cardInstanceId: id }).strict(),
]);

export const scenarioCommandSchema = z.discriminatedUnion('type', [
  z
    .object({ type: z.literal('ATTACK'), actor: id, target: id, card: id })
    .strict(),
  z
    .object({
      type: z.literal('ATTACK_RESPONSE'),
      actor: id,
      response: reactionSchema,
      nowMs: timed,
    })
    .strict(),
  z
    .object({
      type: z.literal('INVESTIGATE'),
      actor: id,
      target: id,
      card: id,
      randomSequence,
      defense: defenseSchema.optional(),
    })
    .strict(),
  z
    .object({
      type: z.literal('PLAY_CARD'),
      actor: id,
      card: id,
      target: id.optional(),
      targets: z.array(id).optional(),
      randomSequence,
    })
    .strict(),
  z.object({ type: z.literal('DISCARD'), actor: id, card: id }).strict(),
  z
    .object({ type: z.literal('BASIC_OBSERVE'), actor: id, target: id })
    .strict(),
  z
    .object({
      type: z.literal('ACCUSE'),
      actor: id,
      response: z.enum(['pass', 'accuse']),
      nowMs: timed,
    })
    .strict(),
  z.object({ type: z.literal('EXPIRE_ACCUSATION'), nowMs: timed }).strict(),
  z
    .object({
      type: z.literal('SECRET_CHOICE'),
      actor: id,
      choice: z.enum(['pass', 'finish']),
      nowMs: timed,
    })
    .strict(),
  z.object({ type: z.literal('EXPIRE_SECRET'), nowMs: timed }).strict(),
  z
    .object({
      type: z.literal('PLAY_LAST_CHANCE'),
      actor: id,
      card: id,
      nowMs: timed,
    })
    .strict(),
  z
    .object({ type: z.literal('PASS_LAST_CHANCE'), actor: id, nowMs: timed })
    .strict(),
  z.object({ type: z.literal('EXPIRE_LAST_CHANCE'), nowMs: timed }).strict(),
  z
    .object({
      type: z.literal('DEPARTURE'),
      actor: id,
      departure: z.discriminatedUnion('kind', [
        z.object({ kind: z.literal('disconnect') }).strict(),
        z.object({ kind: z.literal('forfeit'), nowMs: timed }).strict(),
      ]),
    })
    .strict(),
  z.object({ type: z.literal('END_TURN'), discards: z.array(id) }).strict(),
  z.object({ type: z.literal('BEGIN_TURN'), randomSequence }).strict(),
]);

const scenarioStateSchema = matchStateSchema.partial().extend({
  players: z
    .record(z.string(), matchStateSchema.shape.players.valueSchema.partial())
    .optional(),
});

const scenarioFixtureSchema = z
  .object({
    name: z.string().regex(/^[a-z0-9-]+$/),
    initialState: scenarioStateSchema,
    steps: z
      .array(
        z
          .object({
            command: scenarioCommandSchema,
            expectedError: z.enum(engineErrorCodes).optional(),
            expectedResult: z.record(z.unknown()).optional(),
            expectedPublic: z.record(z.unknown()).optional(),
            absentPublicPaths: z.array(id).optional(),
            expectedPrivate: z
              .record(z.string(), z.record(z.unknown()))
              .optional(),
          })
          .strict(),
      )
      .min(1),
    expectedState: scenarioStateSchema.refine(
      (value) => Object.keys(value).length > 0,
    ),
  })
  .strict();

export const scenarioSuiteSchema = z
  .object({
    fixtureVersion: z.literal(2),
    rulesVersion: z.literal(RULES_VERSION),
    catalogVersion: z.literal(CATALOG_VERSION),
    name: z.string().regex(/^[a-z0-9-]+$/),
    baseState: matchStateSchema,
    scenarios: z.array(scenarioFixtureSchema).min(1),
  })
  .strict()
  .superRefine((suite, context) => {
    const names = new Set<string>();
    suite.scenarios.forEach((scenario, index) => {
      if (names.has(scenario.name)) {
        context.addIssue({
          code: z.ZodIssueCode.custom,
          path: ['scenarios', index, 'name'],
          message: 'Scenario names must be unique',
        });
      }
      names.add(scenario.name);
    });
  });

export type ScenarioCommand = z.infer<typeof scenarioCommandSchema>;

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
  scenarioSuiteSchema,
  stateTransitionFixtureSchema,
  matchSetupFixtureSchema,
  turnStartFixtureSchema,
  endTurnFixtureSchema,
]);

export type GoldenFixture = z.infer<typeof goldenFixtureSchema>;
