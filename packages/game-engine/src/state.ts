import { z } from 'zod';

export const RULES_VERSION = '2.1.0';
export const CATALOG_VERSION = '1.0.0';

export const playerRoleSchema = z.enum(['impostor', 'innocent']);
export const playerStatusSchema = z.enum(['active', 'cornered', 'eliminated']);
export const publicActionKindSchema = z.enum([
  'successful_attack',
  'noisy_manipulation',
]);
const publicActionRecordSchema = z
  .object({
    playerId: z.string().min(1),
    kind: publicActionKindSchema,
  })
  .strict();
export const matchPhaseSchema = z.enum([
  'created',
  'lobby',
  'ready_check',
  'dealing',
  'turn_start',
  'active_turn',
  'awaiting_card_effect',
  'awaiting_reaction',
  'awaiting_accusation',
  'awaiting_secret_finish',
  'awaiting_last_chance',
  'finished',
  'archived',
  'cancelled',
]);

const evidenceSchema = z
  .object({
    clue: z.boolean(),
    behavior: z.boolean(),
  })
  .strict();

const playerStateSchema = z
  .object({
    playerId: z.string().min(1),
    role: playerRoleSchema.nullable(),
    status: playerStatusSchema,
    hearts: z.number().int().min(0).max(3),
    suspicion: z.number().int().min(0).max(3),
    hand: z.array(z.string()),
    evidence: z.record(z.string(), evidenceSchema),
    lastPlayedActionCardInstanceId: z.string().nullable().default(null),
    accusationUsed: z.boolean(),
  })
  .strict();

const activeEffectSchema = z
  .object({
    type: z.literal('safe_place'),
    casterPlayerId: z.string().min(1),
    targetPlayerId: z.string().min(1),
  })
  .strict();
const activeEffectsSchema = z
  .array(activeEffectSchema)
  .superRefine((effects, context) => {
    const shieldedPlayerIds = new Set<string>();
    effects.forEach((effect, index) => {
      if (shieldedPlayerIds.has(effect.targetPlayerId)) {
        context.addIssue({
          code: z.ZodIssueCode.custom,
          message: `Player already has a Safe Place shield: ${effect.targetPlayerId}`,
          path: [index, 'targetPlayerId'],
        });
      }

      shieldedPlayerIds.add(effect.targetPlayerId);
    });
  });

const pendingAttackSchema = z
  .object({
    attackerPlayerId: z.string().min(1),
    targetPlayerId: z.string().min(1),
    attackCardInstanceId: z.string().min(1),
    stepInPlayerIds: z.array(z.string().min(1)),
    stepInIndex: z.number().int().min(-1),
    targetDiscardCardInstanceId: z.string().nullable().default(null),
    calloutRevealedActionCardInstanceId: z.string().nullable().default(null),
  })
  .strict();

const pendingCardEffectSchema = z.discriminatedUnion('kind', [
  z
    .object({
      kind: z.literal('catch_your_breath_discard'),
      actorPlayerId: z.string().min(1),
    })
    .strict(),
  z
    .object({
      kind: z.literal('stir_the_pot_discards'),
      actorPlayerId: z.string().min(1),
      targetPlayerIds: z.tuple([z.string().min(1), z.string().min(1)]),
      responseIndex: z.number().int().min(0).max(1),
    })
    .strict(),
]);

const pendingCorneredSchema = z
  .object({
    attackerPlayerId: z.string().min(1),
    targetPlayerId: z.string().min(1),
    attackCardInstanceId: z.string().min(1),
    accusationOrderPlayerIds: z.array(z.string().min(1)).default([]),
    accusationIndex: z.number().int().min(0).default(0),
    secretFinishResolved: z.boolean().default(false),
  })
  .strict();

const pendingSecretFinishSchema = z
  .object({
    targetPlayerId: z.string().min(1),
    eligiblePlayerIds: z.array(z.string().min(1)),
    submissions: z.record(z.string(), z.enum(['finish', 'pass'])),
  })
  .strict();

const matchOutcomeSchema = z.discriminatedUnion('kind', [
  z.object({ kind: z.literal('winner'), playerId: z.string().min(1) }).strict(),
  z.object({ kind: z.literal('cancelled_no_winner') }).strict(),
]);

export const matchStateSchema = z
  .object({
    matchId: z.string().min(1),
    rulesVersion: z.literal(RULES_VERSION),
    catalogVersion: z.literal(CATALOG_VERSION),
    phase: matchPhaseSchema,
    version: z.number().int().nonnegative(),
    actionsRemaining: z.number().int().min(0).max(2),
    attacksUsedThisTurn: z.number().int().min(0).max(1),
    suspicionAwardedForDamageThisTurn: z.boolean(),
    investigationTargetsThisTurn: z.array(z.string()).default([]),
    currentPlayerId: z.string().nullable(),
    pendingAttack: pendingAttackSchema.nullable().default(null),
    pendingCardEffect: pendingCardEffectSchema.nullable().default(null),
    pendingCornered: pendingCorneredSchema.nullable().default(null),
    pendingSecretFinish: pendingSecretFinishSchema.nullable().default(null),
    seatOrder: z.array(z.string().min(1)).min(4).max(8),
    deadlineUtc: z.string().datetime().nullable(),
    players: z.record(z.string(), playerStateSchema),
    drawPile: z.array(z.string()),
    discardPile: z.array(z.string()),
    publicActionHistory: z.array(publicActionRecordSchema),
    activeEffects: activeEffectsSchema,
    accusationUsed: z.array(z.string()),
    winner: matchOutcomeSchema.nullable(),
  })
  .strict();

export type PlayerRole = z.infer<typeof playerRoleSchema>;
export type PlayerStatus = z.infer<typeof playerStatusSchema>;
export type PublicActionKind = z.infer<typeof publicActionKindSchema>;
export type PublicActionRecord = z.infer<typeof publicActionRecordSchema>;
export type MatchPhase = z.infer<typeof matchPhaseSchema>;
export type PlayerState = z.infer<typeof playerStateSchema>;
export type ActiveEffect = z.infer<typeof activeEffectSchema>;
export type PendingAttack = z.infer<typeof pendingAttackSchema>;
export type PendingCardEffect = z.infer<typeof pendingCardEffectSchema>;
export type PendingCornered = z.infer<typeof pendingCorneredSchema>;
export type PendingSecretFinish = z.infer<typeof pendingSecretFinishSchema>;
export type MatchOutcome = z.infer<typeof matchOutcomeSchema>;
export type MatchState = z.infer<typeof matchStateSchema>;
