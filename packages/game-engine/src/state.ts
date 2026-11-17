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
  'awaiting_reaction',
  'awaiting_accusation',
  'awaiting_secret_finish',
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
    seatOrder: z.array(z.string().min(1)).min(4).max(8),
    deadlineUtc: z.string().datetime().nullable(),
    players: z.record(z.string(), playerStateSchema),
    drawPile: z.array(z.string()),
    discardPile: z.array(z.string()),
    publicActionHistory: z.array(publicActionRecordSchema),
    activeEffects: z.array(z.unknown()),
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
export type MatchOutcome = z.infer<typeof matchOutcomeSchema>;
export type MatchState = z.infer<typeof matchStateSchema>;
