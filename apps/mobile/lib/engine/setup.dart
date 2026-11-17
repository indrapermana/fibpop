import 'card_catalog.dart';
import 'game_state.dart';
import 'random.dart';

MatchState createMatch({
  required String matchId,
  required List<String> playerIds,
  required CardCatalog catalog,
  required RandomSource random,
}) {
  if (matchId.trim().isEmpty ||
      playerIds.length < 4 ||
      playerIds.length > 8 ||
      playerIds.any((id) => id.trim().isEmpty) ||
      playerIds.toSet().length != playerIds.length) {
    throw ArgumentError(
      'Match requires a non-empty ID and 4–8 unique player IDs',
    );
  }
  final roles = [
    PlayerRole.impostor,
    ...List.filled(playerIds.length - 1, PlayerRole.innocent),
  ];
  shuffle(roles, random);
  final deck = <String>[
    for (final card in catalog.cards)
      for (var copy = 1; copy <= card.copies; copy++) '${card.id}:$copy',
  ];
  shuffle(deck, random);

  final players = <String, PlayerState>{};
  for (var index = 0; index < playerIds.length; index++) {
    final playerId = playerIds[index];
    players[playerId] = PlayerState(
      playerId: playerId,
      role: roles[index],
      status: PlayerStatus.active,
      hearts: 3,
      suspicion: 0,
      hand: [for (var card = 0; card < 4; card++) deck.removeLast()],
      evidence: const {},
      lastPlayedActionCardInstanceId: null,
      accusationUsed: false,
    );
  }
  final currentPlayerId = playerIds[randomIndex(playerIds.length, random)];
  return MatchState(
    matchId: matchId,
    phase: TurnPhase.turnStart,
    version: 0,
    actionsRemaining: 0,
    attacksUsedThisTurn: 0,
    suspicionAwardedForDamageThisTurn: false,
    investigationTargetsThisTurn: const [],
    currentPlayerId: currentPlayerId,
    seatOrder: playerIds,
    players: players,
    drawPile: deck,
    discardPile: const [],
    publicActionHistory: const [],
    activeEffects: const [],
    accusationUsed: const [],
  );
}
