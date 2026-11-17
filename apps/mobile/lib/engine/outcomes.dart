import 'game_state.dart';

MatchState? findImpostorWinner(MatchState state) {
  final impostors = state.players.values
      .where((player) => player.role == PlayerRole.impostor)
      .toList();
  if (impostors.length != 1) return null;

  final impostor = impostors.single;
  if (impostor.status == PlayerStatus.eliminated ||
      state.players.values.any(
        (player) =>
            player.role == PlayerRole.innocent &&
            player.status != PlayerStatus.eliminated,
      )) {
    return null;
  }

  return state.copyWith(
    phase: TurnPhase.finished,
    clearCurrentPlayerId: true,
    clearDeadlineUtc: true,
    clearPendingAttack: true,
    clearPendingCornered: true,
    clearPendingSecretFinish: true,
    winner: MatchOutcome.winner(impostor.playerId),
  );
}
