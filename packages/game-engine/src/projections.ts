import { currentAttackResponder } from './attacks.js';
import { currentCardEffectResponder } from './card-effects.js';
import {
  currentAccusationPlayerId,
  currentLastChancePlayerId,
  isEligibleAccuser,
} from './cornered.js';
import { getCardDesignId } from './card-instance.js';
import { EngineError } from './errors.js';
import type {
  ActiveEffect,
  MatchOutcome,
  MatchPhase,
  MatchState,
  PlayerRole,
  PlayerStatus,
  PublicActionRecord,
} from './state.js';

type PublicPhase =
  | Exclude<
      MatchPhase,
      'awaiting_accusation' | 'awaiting_secret_finish' | 'awaiting_last_chance'
    >
  | 'cornered_resolution';

export interface PublicMatchView {
  matchId: string;
  rulesVersion: string;
  catalogVersion: string;
  phase: PublicPhase;
  currentPlayerId: string | null;
  corneredTargetPlayerId: string | null;
  actionsRemaining: number;
  attacksUsedThisTurn: number;
  seatOrder: string[];
  players: Record<
    string,
    {
      playerId: string;
      status: PlayerStatus;
      hearts: number;
      suspicion: number;
      handCount: number;
      revealedRole: PlayerRole | null;
    }
  >;
  drawCount: number;
  discardCount: number;
  attack: {
    attackerPlayerId: string;
    targetPlayerId: string;
    attackCardInstanceId: string;
    calloutRevealedActionCardInstanceId: string | null;
  } | null;
  cardEffect: {
    kind: 'catch_your_breath_discard' | 'stir_the_pot_discards';
    actorPlayerId: string;
    targetPlayerIds: string[];
  } | null;
  activeEffects: ActiveEffect[];
  publicActionHistory: PublicActionRecord[];
  winner: MatchOutcome | null;
}

export type PrivatePrompt =
  | { kind: 'attack_response' }
  | { kind: 'card_effect_discard' }
  | {
      kind: 'accusation';
      targetPlayerId: string;
      deadlineUtc: string;
      canAccuse: boolean;
      submitted: boolean;
    }
  | {
      kind: 'secret_choice';
      deadlineUtc: string;
      canFinish: boolean;
      submitted: boolean;
    }
  | {
      kind: 'last_chance';
      deadlineUtc: string;
      canPlay: boolean;
      submitted: boolean;
    };

export interface PlayerMatchView {
  public: PublicMatchView;
  self: {
    playerId: string;
    role: PlayerRole | null;
    hand: string[];
    evidence: MatchState['players'][string]['evidence'];
    accusationUsed: boolean;
    prompt: PrivatePrompt | null;
  };
}

export function projectPublicState(state: MatchState): PublicMatchView {
  const phase: PublicPhase =
    state.phase === 'awaiting_accusation' ||
    state.phase === 'awaiting_secret_finish' ||
    state.phase === 'awaiting_last_chance'
      ? 'cornered_resolution'
      : state.phase;
  const players: PublicMatchView['players'] = Object.fromEntries(
    state.seatOrder.map((id) => {
      const player = state.players[id];
      if (!player) {
        throw new EngineError(
          'INVALID_PLAYER',
          'A seat is missing its player state',
        );
      }
      const revealedAtFinish =
        state.phase === 'finished' &&
        state.winner?.kind === 'winner' &&
        (state.winner.playerId === id || player.role === 'impostor');
      return [
        id,
        {
          playerId: id,
          status: player.status,
          hearts: player.hearts,
          suspicion: player.suspicion,
          handCount: player.hand.length,
          revealedRole:
            player.status === 'eliminated' || revealedAtFinish
              ? player.role
              : null,
        },
      ];
    }),
  );
  return {
    matchId: state.matchId,
    rulesVersion: state.rulesVersion,
    catalogVersion: state.catalogVersion,
    phase,
    currentPlayerId: state.currentPlayerId,
    corneredTargetPlayerId:
      phase === 'cornered_resolution'
        ? (state.pendingCornered?.targetPlayerId ?? null)
        : null,
    actionsRemaining: state.actionsRemaining,
    attacksUsedThisTurn: state.attacksUsedThisTurn,
    seatOrder: [...state.seatOrder],
    players,
    drawCount: state.drawPile.length,
    discardCount: state.discardPile.length,
    attack:
      state.phase === 'awaiting_reaction' && state.pendingAttack
        ? {
            attackerPlayerId: state.pendingAttack.attackerPlayerId,
            targetPlayerId: state.pendingAttack.targetPlayerId,
            attackCardInstanceId: state.pendingAttack.attackCardInstanceId,
            calloutRevealedActionCardInstanceId:
              state.pendingAttack.calloutRevealedActionCardInstanceId,
          }
        : null,
    cardEffect:
      state.phase === 'awaiting_card_effect' && state.pendingCardEffect
        ? {
            kind: state.pendingCardEffect.kind,
            actorPlayerId: state.pendingCardEffect.actorPlayerId,
            targetPlayerIds:
              state.pendingCardEffect.kind === 'stir_the_pot_discards'
                ? [...state.pendingCardEffect.targetPlayerIds]
                : [],
          }
        : null,
    activeEffects: state.activeEffects.map((effect) => ({ ...effect })),
    publicActionHistory: state.publicActionHistory.map((action) => ({
      ...action,
    })),
    winner: state.winner ? { ...state.winner } : null,
  };
}

export function projectPlayerState(
  state: MatchState,
  playerId: string,
): PlayerMatchView {
  const player = state.players[playerId];
  if (!player || !state.seatOrder.includes(playerId)) {
    throw new EngineError(
      'INVALID_PLAYER',
      'The player must belong to the match',
    );
  }
  let prompt: PrivatePrompt | null = null;
  if (currentAttackResponder(state) === playerId) {
    prompt = { kind: 'attack_response' };
  } else if (currentCardEffectResponder(state) === playerId) {
    prompt = { kind: 'card_effect_discard' };
  } else if (
    currentAccusationPlayerId(state) === playerId &&
    player.status === 'active' &&
    state.pendingCornered &&
    state.deadlineUtc
  ) {
    prompt = {
      kind: 'accusation',
      targetPlayerId: state.pendingCornered.targetPlayerId,
      deadlineUtc: state.deadlineUtc,
      canAccuse: isEligibleAccuser(
        state,
        playerId,
        state.pendingCornered.targetPlayerId,
      ),
      submitted: state.pendingCornered.accusationPassed,
    };
  } else if (
    state.phase === 'awaiting_secret_finish' &&
    state.pendingSecretFinish?.eligiblePlayerIds.includes(playerId) &&
    state.deadlineUtc
  ) {
    prompt = {
      kind: 'secret_choice',
      deadlineUtc: state.deadlineUtc,
      canFinish: player.role === 'impostor',
      submitted: Object.hasOwn(state.pendingSecretFinish.submissions, playerId),
    };
  } else if (
    currentLastChancePlayerId(state) === playerId &&
    state.pendingCornered &&
    state.deadlineUtc
  ) {
    prompt = {
      kind: 'last_chance',
      deadlineUtc: state.deadlineUtc,
      canPlay: player.hand.some((card) => getCardDesignId(card) === 'card_19'),
      submitted: state.pendingCornered.lastChanceChoice !== null,
    };
  }
  return {
    public: projectPublicState(state),
    self: {
      playerId,
      role: player.role,
      hand: [...player.hand],
      evidence: Object.fromEntries(
        Object.entries(player.evidence).map(([id, evidence]) => [
          id,
          { ...evidence },
        ]),
      ),
      accusationUsed: player.accusationUsed,
      prompt,
    },
  };
}
