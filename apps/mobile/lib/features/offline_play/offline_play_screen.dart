import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../engine/game_state.dart';
import '../../engine/random.dart';
import '../../engine/setup.dart';
import '../../engine/turns.dart';
import '../../l10n/generated/app_localizations.dart';
import '../rules/card_text.dart';
import 'card_catalog_provider.dart';

class OfflinePlayScreen extends ConsumerStatefulWidget {
  const OfflinePlayScreen({super.key});

  @override
  ConsumerState<OfflinePlayScreen> createState() => _OfflinePlayScreenState();
}

class _OfflinePlayScreenState extends ConsumerState<OfflinePlayScreen> {
  final _random = _LocalRandomSource();
  MatchState? _state;
  int _playerCount = 4;
  bool _showCurrentRole = false;

  void _startMatch() {
    final catalog = ref.read(offlineCardCatalogProvider).valueOrNull;
    if (catalog == null) return;
    final match = createMatch(
      matchId: 'offline-${DateTime.now().microsecondsSinceEpoch}',
      playerIds: [
        for (var index = 1; index <= _playerCount; index++) 'player-$index',
      ],
      catalog: catalog,
      random: _random,
    );
    setState(() {
      _state = beginTurn(match, _random);
      _showCurrentRole = false;
    });
  }

  Future<void> _endTurn(AppLocalizations strings) async {
    final state = _state;
    final playerId = state?.currentPlayerId;
    if (state == null || playerId == null) return;
    final hand = state.players[playerId]!.hand;
    final excess = (hand.length - 7).clamp(0, hand.length);
    final discards = excess == 0
        ? <String>[]
        : await _chooseDiscards(hand, excess, strings);
    if (discards == null || !mounted) return;

    final nextTurn = endTurn(state, discards);
    setState(() {
      _state = beginTurn(nextTurn, _random);
      _showCurrentRole = false;
    });
  }

  Future<List<String>?> _chooseDiscards(
    List<String> hand,
    int count,
    AppLocalizations strings,
  ) => showDialog<List<String>>(
    context: context,
    builder: (context) {
      final selected = <String>{};
      return StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(strings.offlineDiscardExcess(count)),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final card in hand)
                  CheckboxListTile(
                    value: selected.contains(card),
                    title: Text(card),
                    onChanged: (value) => setDialogState(() {
                      if (value == true) {
                        if (selected.length < count) selected.add(card);
                      } else {
                        selected.remove(card);
                      }
                    }),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(strings.offlineCancel),
            ),
            FilledButton(
              onPressed: selected.length == count
                  ? () => Navigator.pop(context, selected.toList())
                  : null,
              child: Text(strings.offlineConfirm),
            ),
          ],
        ),
      );
    },
  );

  String _phaseLabel(AppLocalizations strings, TurnPhase phase) =>
      switch (phase) {
        TurnPhase.turnStart => strings.offlinePhaseTurnStart,
        TurnPhase.activeTurn => strings.offlinePhaseActiveTurn,
        TurnPhase.awaitingReaction => strings.offlinePhaseAwaitingReaction,
        TurnPhase.awaitingCardEffect => strings.offlinePhaseAwaitingCardEffect,
        TurnPhase.awaitingAccusation ||
        TurnPhase.awaitingSecretFinish ||
        TurnPhase.awaitingLastChance => strings.offlinePhaseCorneredResolution,
        TurnPhase.finished => strings.offlinePhaseFinished,
        TurnPhase.cancelled => strings.offlinePhaseCancelled,
      };

  String _statusLabel(AppLocalizations strings, PlayerStatus status) =>
      switch (status) {
        PlayerStatus.active => strings.offlineActive,
        PlayerStatus.cornered => strings.offlineCornered,
        PlayerStatus.eliminated => strings.offlineEliminated,
      };

  String _roleLabel(AppLocalizations strings, PlayerRole? role) =>
      switch (role) {
        PlayerRole.impostor => strings.offlineImpostor,
        PlayerRole.innocent => strings.offlineInnocent,
        null => '—',
      };

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final state = _state;
    return Scaffold(
      appBar: AppBar(title: Text(strings.offlinePlay)),
      body: state == null ? _buildSetup(strings) : _buildTable(strings, state),
    );
  }

  Widget _buildSetup(AppLocalizations strings) {
    final catalog = ref.watch(offlineCardCatalogProvider);
    final cardText = ref.watch(cardTextProvider);
    final loadingError = catalog.hasError || cardText.hasError;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                strings.offlineMatchSetup,
                style: Theme.of(context).textTheme.headlineSmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              DropdownButtonFormField<int>(
                initialValue: _playerCount,
                decoration: InputDecoration(
                  labelText: strings.offlinePlayerCount,
                  border: const OutlineInputBorder(),
                ),
                items: [
                  for (var count = 4; count <= 8; count++)
                    DropdownMenuItem(value: count, child: Text('$count')),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => _playerCount = value);
                },
              ),
              const SizedBox(height: 16),
              if (loadingError)
                Text(
                  strings.contentLoadError,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                  textAlign: TextAlign.center,
                )
              else if (catalog.isLoading || cardText.isLoading)
                const Center(child: CircularProgressIndicator())
              else
                FilledButton(
                  onPressed: _startMatch,
                  child: Text(strings.offlineStartMatch),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTable(AppLocalizations strings, MatchState state) {
    final language = Localizations.localeOf(context).languageCode;
    final cardTexts = ref.watch(cardTextProvider).valueOrNull ?? const [];
    final cardById = {for (final card in cardTexts) card.id: card};
    final currentPlayerId = state.currentPlayerId!;
    final currentPlayer = state.players[currentPlayerId]!;
    final evidenceEntries = currentPlayer.evidence.entries.toList()
      ..sort((left, right) => left.key.compareTo(right.key));
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _phaseLabel(strings, state.phase),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                Text(
                  '${strings.offlineYou}: ${strings.offlinePlayer(state.seatOrder.indexOf(currentPlayerId) + 1)}',
                ),
                Text(strings.offlineActionsRemaining(state.actionsRemaining)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    Chip(
                      label: Text(
                        strings.offlineDrawPile(state.drawPile.length),
                      ),
                    ),
                    Chip(
                      label: Text(
                        strings.offlineDiscardPile(state.discardPile.length),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () =>
                      setState(() => _showCurrentRole = !_showCurrentRole),
                  icon: const Icon(Icons.visibility),
                  label: Text(
                    _showCurrentRole
                        ? strings.offlineHideRole
                        : strings.offlineRevealRole,
                  ),
                ),
                if (_showCurrentRole)
                  Text(
                    '${strings.offlineRole}: ${_roleLabel(strings, currentPlayer.role)}',
                    key: const Key('offline-private-role'),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          strings.offlinePlayerCount,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        for (var seat = 0; seat < state.seatOrder.length; seat++)
          _PlayerSeat(
            title: strings.offlinePlayer(seat + 1),
            player: state.players[state.seatOrder[seat]]!,
            statusLabel: _statusLabel(
              strings,
              state.players[state.seatOrder[seat]]!.status,
            ),
            heartsLabel: strings.offlineHearts,
            suspicionLabel: strings.offlineSuspicion,
            isCurrent: state.seatOrder[seat] == currentPlayerId,
          ),
        const SizedBox(height: 16),
        Text(
          strings.offlineEvidence,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        if (evidenceEntries.isEmpty)
          Text(strings.offlineNoEvidence)
        else
          for (final entry in evidenceEntries)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                strings.offlinePlayer(state.seatOrder.indexOf(entry.key) + 1),
              ),
              subtitle: Text(
                [
                  if (entry.value.clue) strings.offlineClue,
                  if (entry.value.behavior) strings.offlineBehavior,
                ].join(' · '),
              ),
            ),
        const SizedBox(height: 8),
        Text(
          strings.offlineHand,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        for (final cardId in currentPlayer.hand)
          _HandCard(
            cardId: cardId,
            name:
                cardById[_designId(cardId)]?.forLanguage(language).name ??
                cardId,
            text: cardById[_designId(cardId)]?.forLanguage(language).text ?? '',
          ),
        const SizedBox(height: 8),
        Text(
          strings.offlineActionsComingSoon,
          style: Theme.of(context).textTheme.bodySmall,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        FilledButton(
          onPressed: state.phase == TurnPhase.activeTurn
              ? () => _endTurn(strings)
              : null,
          child: Text(strings.offlineEndTurn),
        ),
      ],
    );
  }

  String _designId(String instanceId) =>
      RegExp(r'^(card_\d{2}):').firstMatch(instanceId)?.group(1) ?? instanceId;
}

class _PlayerSeat extends StatelessWidget {
  const _PlayerSeat({
    required this.title,
    required this.player,
    required this.statusLabel,
    required this.heartsLabel,
    required this.suspicionLabel,
    required this.isCurrent,
  });

  final String title;
  final PlayerState player;
  final String statusLabel;
  final String heartsLabel;
  final String suspicionLabel;
  final bool isCurrent;

  @override
  Widget build(BuildContext context) => Card(
    color: isCurrent ? Theme.of(context).colorScheme.secondaryContainer : null,
    child: ListTile(
      title: Text(title),
      subtitle: Text(
        '$statusLabel · $heartsLabel: ${player.hearts} · $suspicionLabel: ${player.suspicion}',
      ),
      trailing: isCurrent ? const Icon(Icons.arrow_forward) : null,
    ),
  );
}

class _HandCard extends StatelessWidget {
  const _HandCard({
    required this.cardId,
    required this.name,
    required this.text,
  });

  final String cardId;
  final String name;
  final String text;

  @override
  Widget build(BuildContext context) => Card(
    child: ListTile(
      leading: const Icon(Icons.style),
      title: Text(name),
      subtitle: Text(text.replaceAll('**', '')),
      trailing: Text(cardId),
    ),
  );
}

class _LocalRandomSource implements RandomSource {
  final _random = Random();

  @override
  double next() => _random.nextDouble();
}
