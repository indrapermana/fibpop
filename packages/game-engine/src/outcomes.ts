import { matchStateSchema, type MatchState } from './state.js';

export function findImpostorWinner(state: MatchState): MatchState | null {
  const impostor = Object.values(state.players).find(
    (player) => player.role === 'impostor',
  );
  if (
    !impostor ||
    impostor.status === 'eliminated' ||
    Object.values(state.players).some(
      (player) => player.role === 'innocent' && player.status !== 'eliminated',
    )
  ) {
    return null;
  }

  return matchStateSchema.parse({
    ...state,
    phase: 'finished',
    currentPlayerId: null,
    deadlineUtc: null,
    pendingAttack: null,
    pendingCardEffect: null,
    pendingCornered: null,
    pendingSecretFinish: null,
    winner: { kind: 'winner', playerId: impostor.playerId },
  });
}
