import 'card_catalog.dart';

const rulesVersion = '2.1.0';

enum PlayerRole { impostor, innocent }

enum PlayerStatus { active, cornered, eliminated }

enum TurnPhase {
  turnStart('turn_start'),
  activeTurn('active_turn'),
  awaitingCardEffect('awaiting_card_effect'),
  awaitingReaction('awaiting_reaction'),
  awaitingAccusation('awaiting_accusation'),
  awaitingSecretFinish('awaiting_secret_finish'),
  awaitingLastChance('awaiting_last_chance'),
  finished('finished'),
  cancelled('cancelled');

  const TurnPhase(this.wireValue);
  final String wireValue;
}

class Evidence {
  const Evidence({required this.clue, required this.behavior});

  final bool clue;
  final bool behavior;

  factory Evidence.fromJson(Map<String, Object?> json) {
    _checkKeys(json, {'clue', 'behavior'});
    return Evidence(
      clue: _value<bool>(json, 'clue'),
      behavior: _value<bool>(json, 'behavior'),
    );
  }

  Map<String, Object?> toJson() => {'clue': clue, 'behavior': behavior};
}

class PlayerState {
  PlayerState({
    required this.playerId,
    required this.role,
    required this.status,
    required this.hearts,
    required this.suspicion,
    required List<String> hand,
    required Map<String, Evidence> evidence,
    required this.lastPlayedActionCardInstanceId,
    required this.accusationUsed,
  }) : hand = List.unmodifiable(hand),
       evidence = Map.unmodifiable(evidence);

  final String playerId;
  final PlayerRole? role;
  final PlayerStatus status;
  final int hearts;
  final int suspicion;
  final List<String> hand;
  final Map<String, Evidence> evidence;
  final String? lastPlayedActionCardInstanceId;
  final bool accusationUsed;

  factory PlayerState.fromJson(Map<String, Object?> json) {
    _checkKeys(
      json,
      {
        'playerId',
        'role',
        'status',
        'hearts',
        'suspicion',
        'hand',
        'evidence',
        'accusationUsed',
      },
      optional: {'lastPlayedActionCardInstanceId'},
    );
    final roleValue = json['role'];
    PlayerRole? role;
    if (roleValue is String) {
      role = _enumByName(PlayerRole.values, roleValue, 'role');
    } else if (roleValue != null) {
      throw const FormatException('Invalid player role');
    }
    final hearts = _value<int>(json, 'hearts');
    final suspicion = _value<int>(json, 'suspicion');
    if (hearts < 0 || hearts > 3 || suspicion < 0 || suspicion > 3) {
      throw const FormatException(
        'Hearts and suspicion must be between 0 and 3',
      );
    }
    final evidence = _object(json, 'evidence').map(
      (key, value) => MapEntry(key, Evidence.fromJson(_asObject(value, key))),
    );
    return PlayerState(
      playerId: _nonemptyString(json, 'playerId'),
      role: role,
      status: _enumByName(
        PlayerStatus.values,
        _value<String>(json, 'status'),
        'status',
      ),
      hearts: hearts,
      suspicion: suspicion,
      hand: _strings(json, 'hand'),
      evidence: evidence,
      lastPlayedActionCardInstanceId: _nullableString(
        json,
        'lastPlayedActionCardInstanceId',
      ),
      accusationUsed: _value<bool>(json, 'accusationUsed'),
    );
  }

  PlayerState copyWith({
    PlayerStatus? status,
    int? hearts,
    int? suspicion,
    List<String>? hand,
    Map<String, Evidence>? evidence,
    String? lastPlayedActionCardInstanceId,
    bool? accusationUsed,
  }) => PlayerState(
    playerId: playerId,
    role: role,
    status: status ?? this.status,
    hearts: hearts ?? this.hearts,
    suspicion: suspicion ?? this.suspicion,
    hand: hand ?? this.hand,
    evidence: evidence ?? this.evidence,
    lastPlayedActionCardInstanceId:
        lastPlayedActionCardInstanceId ?? this.lastPlayedActionCardInstanceId,
    accusationUsed: accusationUsed ?? this.accusationUsed,
  );

  Map<String, Object?> toJson() => {
    'playerId': playerId,
    'role': role?.name,
    'status': status.name,
    'hearts': hearts,
    'suspicion': suspicion,
    'hand': hand,
    'evidence': evidence.map((key, value) => MapEntry(key, value.toJson())),
    'lastPlayedActionCardInstanceId': lastPlayedActionCardInstanceId,
    'accusationUsed': accusationUsed,
  };
}

class PublicAction {
  const PublicAction({required this.playerId, required this.kind});

  final String playerId;
  final String kind;

  factory PublicAction.fromJson(Map<String, Object?> json) {
    _checkKeys(json, {'playerId', 'kind'});
    final kind = _value<String>(json, 'kind');
    if (kind != 'successful_attack' && kind != 'noisy_manipulation') {
      throw const FormatException('Invalid public action');
    }
    return PublicAction(
      playerId: _nonemptyString(json, 'playerId'),
      kind: kind,
    );
  }

  Map<String, Object?> toJson() => {'playerId': playerId, 'kind': kind};
}

class SafePlaceEffect {
  const SafePlaceEffect({
    required this.casterPlayerId,
    required this.targetPlayerId,
  });

  final String casterPlayerId;
  final String targetPlayerId;

  factory SafePlaceEffect.fromJson(Map<String, Object?> json) {
    _checkKeys(json, {'type', 'casterPlayerId', 'targetPlayerId'});
    if (json['type'] != 'safe_place') {
      throw const FormatException('Invalid active effect');
    }
    return SafePlaceEffect(
      casterPlayerId: _nonemptyString(json, 'casterPlayerId'),
      targetPlayerId: _nonemptyString(json, 'targetPlayerId'),
    );
  }

  Map<String, Object?> toJson() => {
    'type': 'safe_place',
    'casterPlayerId': casterPlayerId,
    'targetPlayerId': targetPlayerId,
  };
}

class PendingAttack {
  PendingAttack({
    required this.attackerPlayerId,
    required this.targetPlayerId,
    required this.attackCardInstanceId,
    required List<String> stepInPlayerIds,
    required this.stepInIndex,
    required this.targetDiscardCardInstanceId,
    required this.calloutRevealedActionCardInstanceId,
  }) : stepInPlayerIds = List.unmodifiable(stepInPlayerIds);

  final String attackerPlayerId;
  final String targetPlayerId;
  final String attackCardInstanceId;
  final List<String> stepInPlayerIds;
  final int stepInIndex;
  final String? targetDiscardCardInstanceId;
  final String? calloutRevealedActionCardInstanceId;

  factory PendingAttack.fromJson(Map<String, Object?> json) {
    _checkKeys(json, {
      'attackerPlayerId',
      'targetPlayerId',
      'attackCardInstanceId',
      'stepInPlayerIds',
      'stepInIndex',
      'targetDiscardCardInstanceId',
      'calloutRevealedActionCardInstanceId',
    });
    final index = _value<int>(json, 'stepInIndex');
    if (index < -1) throw const FormatException('Invalid Step In index');
    return PendingAttack(
      attackerPlayerId: _nonemptyString(json, 'attackerPlayerId'),
      targetPlayerId: _nonemptyString(json, 'targetPlayerId'),
      attackCardInstanceId: _nonemptyString(json, 'attackCardInstanceId'),
      stepInPlayerIds: _strings(json, 'stepInPlayerIds'),
      stepInIndex: index,
      targetDiscardCardInstanceId: _nullableString(
        json,
        'targetDiscardCardInstanceId',
      ),
      calloutRevealedActionCardInstanceId: _nullableString(
        json,
        'calloutRevealedActionCardInstanceId',
      ),
    );
  }

  Map<String, Object?> toJson() => {
    'attackerPlayerId': attackerPlayerId,
    'targetPlayerId': targetPlayerId,
    'attackCardInstanceId': attackCardInstanceId,
    'stepInPlayerIds': stepInPlayerIds,
    'stepInIndex': stepInIndex,
    'targetDiscardCardInstanceId': targetDiscardCardInstanceId,
    'calloutRevealedActionCardInstanceId': calloutRevealedActionCardInstanceId,
  };

  PendingAttack copyWith({
    List<String>? stepInPlayerIds,
    int? stepInIndex,
    String? targetDiscardCardInstanceId,
  }) => PendingAttack(
    attackerPlayerId: attackerPlayerId,
    targetPlayerId: targetPlayerId,
    attackCardInstanceId: attackCardInstanceId,
    stepInPlayerIds: stepInPlayerIds ?? this.stepInPlayerIds,
    stepInIndex: stepInIndex ?? this.stepInIndex,
    targetDiscardCardInstanceId:
        targetDiscardCardInstanceId ?? this.targetDiscardCardInstanceId,
    calloutRevealedActionCardInstanceId: calloutRevealedActionCardInstanceId,
  );
}

class PendingCardEffect {
  PendingCardEffect.catchYourBreath(this.actorPlayerId)
    : kind = 'catch_your_breath_discard',
      targetPlayerIds = const [],
      responseIndex = 0;

  PendingCardEffect.stirThePot(
    this.actorPlayerId,
    List<String> targetPlayerIds,
    this.responseIndex,
  ) : kind = 'stir_the_pot_discards',
      targetPlayerIds = List.unmodifiable(targetPlayerIds);

  final String kind;
  final String actorPlayerId;
  final List<String> targetPlayerIds;
  final int responseIndex;

  factory PendingCardEffect.fromJson(Map<String, Object?> json) {
    final kind = _value<String>(json, 'kind');
    final actorPlayerId = _nonemptyString(json, 'actorPlayerId');
    if (kind == 'catch_your_breath_discard') {
      _checkKeys(json, {'kind', 'actorPlayerId'});
      return PendingCardEffect.catchYourBreath(actorPlayerId);
    }
    if (kind == 'stir_the_pot_discards') {
      _checkKeys(json, {
        'kind',
        'actorPlayerId',
        'targetPlayerIds',
        'responseIndex',
      });
      final targets = _strings(json, 'targetPlayerIds');
      final index = _value<int>(json, 'responseIndex');
      if (targets.length != 2 || index < 0 || index > 1) {
        throw const FormatException('Invalid Stir the Pot response state');
      }
      return PendingCardEffect.stirThePot(actorPlayerId, targets, index);
    }
    throw const FormatException('Invalid pending card effect');
  }

  PendingCardEffect copyWith({int? responseIndex}) {
    if (kind != 'stir_the_pot_discards') {
      throw StateError('Only Stir the Pot has a response index');
    }
    return PendingCardEffect.stirThePot(
      actorPlayerId,
      targetPlayerIds,
      responseIndex ?? this.responseIndex,
    );
  }

  Map<String, Object?> toJson() => {
    'kind': kind,
    'actorPlayerId': actorPlayerId,
    if (kind == 'stir_the_pot_discards') ...{
      'targetPlayerIds': targetPlayerIds,
      'responseIndex': responseIndex,
    },
  };
}

class LastChanceChoice {
  const LastChanceChoice.pass() : kind = 'pass', cardInstanceId = null;
  const LastChanceChoice.play(this.cardInstanceId) : kind = 'play';

  final String kind;
  final String? cardInstanceId;

  factory LastChanceChoice.fromJson(Map<String, Object?> json) {
    final kind = _value<String>(json, 'kind');
    if (kind == 'pass') {
      _checkKeys(json, {'kind'});
      return const LastChanceChoice.pass();
    }
    if (kind == 'play') {
      _checkKeys(json, {'kind', 'cardInstanceId'});
      return LastChanceChoice.play(_nonemptyString(json, 'cardInstanceId'));
    }
    throw const FormatException('Invalid Last Chance choice');
  }

  Map<String, Object?> toJson() => {
    'kind': kind,
    if (cardInstanceId != null) 'cardInstanceId': cardInstanceId,
  };
}

class PendingCornered {
  PendingCornered({
    required this.attackerPlayerId,
    required this.targetPlayerId,
    required this.attackCardInstanceId,
    required List<String> accusationOrderPlayerIds,
    required this.accusationIndex,
    required this.accusationPassed,
    required this.secretFinishResolved,
    required this.lastChanceChoice,
  }) : accusationOrderPlayerIds = List.unmodifiable(accusationOrderPlayerIds);

  final String attackerPlayerId;
  final String targetPlayerId;
  final String attackCardInstanceId;
  final List<String> accusationOrderPlayerIds;
  final int accusationIndex;
  final bool accusationPassed;
  final bool secretFinishResolved;
  final LastChanceChoice? lastChanceChoice;

  factory PendingCornered.fromJson(Map<String, Object?> json) {
    _checkKeys(json, {
      'attackerPlayerId',
      'targetPlayerId',
      'attackCardInstanceId',
      'accusationOrderPlayerIds',
      'accusationIndex',
      'accusationPassed',
      'secretFinishResolved',
      'lastChanceChoice',
    });
    final index = _value<int>(json, 'accusationIndex');
    if (index < 0) throw const FormatException('Invalid accusation index');
    final lastChance = json['lastChanceChoice'];
    return PendingCornered(
      attackerPlayerId: _nonemptyString(json, 'attackerPlayerId'),
      targetPlayerId: _nonemptyString(json, 'targetPlayerId'),
      attackCardInstanceId: _nonemptyString(json, 'attackCardInstanceId'),
      accusationOrderPlayerIds: _strings(json, 'accusationOrderPlayerIds'),
      accusationIndex: index,
      accusationPassed: _value<bool>(json, 'accusationPassed'),
      secretFinishResolved: _value<bool>(json, 'secretFinishResolved'),
      lastChanceChoice: lastChance == null
          ? null
          : LastChanceChoice.fromJson(
              _asObject(lastChance, 'lastChanceChoice'),
            ),
    );
  }

  Map<String, Object?> toJson() => {
    'attackerPlayerId': attackerPlayerId,
    'targetPlayerId': targetPlayerId,
    'attackCardInstanceId': attackCardInstanceId,
    'accusationOrderPlayerIds': accusationOrderPlayerIds,
    'accusationIndex': accusationIndex,
    'accusationPassed': accusationPassed,
    'secretFinishResolved': secretFinishResolved,
    'lastChanceChoice': lastChanceChoice?.toJson(),
  };

  PendingCornered copyWith({
    List<String>? accusationOrderPlayerIds,
    int? accusationIndex,
    bool? accusationPassed,
    bool? secretFinishResolved,
    LastChanceChoice? lastChanceChoice,
    bool clearLastChanceChoice = false,
  }) => PendingCornered(
    attackerPlayerId: attackerPlayerId,
    targetPlayerId: targetPlayerId,
    attackCardInstanceId: attackCardInstanceId,
    accusationOrderPlayerIds:
        accusationOrderPlayerIds ?? this.accusationOrderPlayerIds,
    accusationIndex: accusationIndex ?? this.accusationIndex,
    accusationPassed: accusationPassed ?? this.accusationPassed,
    secretFinishResolved: secretFinishResolved ?? this.secretFinishResolved,
    lastChanceChoice: clearLastChanceChoice
        ? null
        : lastChanceChoice ?? this.lastChanceChoice,
  );
}

class PendingSecretFinish {
  PendingSecretFinish({
    required this.targetPlayerId,
    required List<String> eligiblePlayerIds,
    required Map<String, String> submissions,
  }) : eligiblePlayerIds = List.unmodifiable(eligiblePlayerIds),
       submissions = Map.unmodifiable(submissions);

  final String targetPlayerId;
  final List<String> eligiblePlayerIds;
  final Map<String, String> submissions;

  factory PendingSecretFinish.fromJson(Map<String, Object?> json) {
    _checkKeys(json, {'targetPlayerId', 'eligiblePlayerIds', 'submissions'});
    final submissions = _object(json, 'submissions');
    if (submissions.values.any(
      (choice) => choice != 'finish' && choice != 'pass',
    )) {
      throw const FormatException('Invalid Secret Finish submission');
    }
    return PendingSecretFinish(
      targetPlayerId: _nonemptyString(json, 'targetPlayerId'),
      eligiblePlayerIds: _strings(json, 'eligiblePlayerIds'),
      submissions: submissions.map(
        (key, value) => MapEntry(key, value as String),
      ),
    );
  }

  Map<String, Object?> toJson() => {
    'targetPlayerId': targetPlayerId,
    'eligiblePlayerIds': eligiblePlayerIds,
    'submissions': submissions,
  };
}

class MatchOutcome {
  const MatchOutcome.winner(this.playerId) : kind = 'winner';
  const MatchOutcome.cancelled()
    : kind = 'cancelled_no_winner',
      playerId = null;

  final String kind;
  final String? playerId;

  factory MatchOutcome.fromJson(Map<String, Object?> json) {
    final kind = _value<String>(json, 'kind');
    if (kind == 'winner') {
      _checkKeys(json, {'kind', 'playerId'});
      return MatchOutcome.winner(_nonemptyString(json, 'playerId'));
    }
    if (kind == 'cancelled_no_winner') {
      _checkKeys(json, {'kind'});
      return const MatchOutcome.cancelled();
    }
    throw const FormatException('Invalid match outcome');
  }

  Map<String, Object?> toJson() => {
    'kind': kind,
    if (playerId != null) 'playerId': playerId,
  };
}

class MatchState {
  MatchState({
    required this.matchId,
    required this.phase,
    required this.version,
    required this.actionsRemaining,
    required this.attacksUsedThisTurn,
    required this.suspicionAwardedForDamageThisTurn,
    required List<String> investigationTargetsThisTurn,
    required this.currentPlayerId,
    required List<String> seatOrder,
    required Map<String, PlayerState> players,
    required List<String> drawPile,
    required List<String> discardPile,
    required List<PublicAction> publicActionHistory,
    required List<SafePlaceEffect> activeEffects,
    required List<String> accusationUsed,
    this.pendingAttack,
    this.pendingCardEffect,
    this.pendingCornered,
    this.pendingSecretFinish,
    this.deadlineUtc,
    this.winner,
  }) : investigationTargetsThisTurn = List.unmodifiable(
         investigationTargetsThisTurn,
       ),
       seatOrder = List.unmodifiable(seatOrder),
       players = Map.unmodifiable(players),
       drawPile = List.unmodifiable(drawPile),
       discardPile = List.unmodifiable(discardPile),
       publicActionHistory = List.unmodifiable(publicActionHistory),
       activeEffects = List.unmodifiable(activeEffects),
       accusationUsed = List.unmodifiable(accusationUsed);

  final String matchId;
  final TurnPhase phase;
  final int version;
  final int actionsRemaining;
  final int attacksUsedThisTurn;
  final bool suspicionAwardedForDamageThisTurn;
  final List<String> investigationTargetsThisTurn;
  final String? currentPlayerId;
  final List<String> seatOrder;
  final Map<String, PlayerState> players;
  final List<String> drawPile;
  final List<String> discardPile;
  final List<PublicAction> publicActionHistory;
  final List<SafePlaceEffect> activeEffects;
  final List<String> accusationUsed;
  final PendingAttack? pendingAttack;
  final PendingCardEffect? pendingCardEffect;
  final PendingCornered? pendingCornered;
  final PendingSecretFinish? pendingSecretFinish;
  final String? deadlineUtc;
  final MatchOutcome? winner;

  factory MatchState.fromJson(Map<String, Object?> json) {
    _checkKeys(
      json,
      {
        'matchId',
        'rulesVersion',
        'catalogVersion',
        'phase',
        'version',
        'actionsRemaining',
        'attacksUsedThisTurn',
        'suspicionAwardedForDamageThisTurn',
        'currentPlayerId',
        'seatOrder',
        'deadlineUtc',
        'players',
        'drawPile',
        'discardPile',
        'publicActionHistory',
        'activeEffects',
        'accusationUsed',
        'winner',
      },
      optional: {
        'investigationTargetsThisTurn',
        'pendingAttack',
        'pendingCardEffect',
        'pendingCornered',
        'pendingSecretFinish',
      },
    );
    if (json['rulesVersion'] != rulesVersion ||
        json['catalogVersion'] != catalogVersion) {
      throw const FormatException('Unsupported rules or catalog version');
    }
    final phase = _value<String>(json, 'phase');
    final turnPhase = TurnPhase.values.where(
      (value) => value.wireValue == phase,
    );
    if (turnPhase.isEmpty) {
      throw UnsupportedError('Phase $phase is not supported yet');
    }
    final seats = _strings(json, 'seatOrder');
    if (seats.length < 4 || seats.length > 8 || seats.any((id) => id.isEmpty)) {
      throw const FormatException('Seat order must contain 4–8 players');
    }
    final version = _value<int>(json, 'version');
    final actions = _value<int>(json, 'actionsRemaining');
    final attacks = _value<int>(json, 'attacksUsedThisTurn');
    if (version < 0 ||
        actions < 0 ||
        actions > 2 ||
        attacks < 0 ||
        attacks > 1) {
      throw const FormatException('Invalid turn resources');
    }
    final players = _object(json, 'players').map(
      (key, value) =>
          MapEntry(key, PlayerState.fromJson(_asObject(value, key))),
    );
    final history = _list(json, 'publicActionHistory')
        .map(
          (value) => PublicAction.fromJson(_asObject(value, 'public action')),
        )
        .toList();
    final effects = _list(json, 'activeEffects')
        .map(
          (value) =>
              SafePlaceEffect.fromJson(_asObject(value, 'active effect')),
        )
        .toList();
    if (effects.map((effect) => effect.targetPlayerId).toSet().length !=
        effects.length) {
      throw const FormatException('Duplicate Safe Place target');
    }
    final pendingAttack = json['pendingAttack'] == null
        ? null
        : PendingAttack.fromJson(
            _asObject(json['pendingAttack'], 'pendingAttack'),
          );
    final pendingCardEffect = json['pendingCardEffect'] == null
        ? null
        : PendingCardEffect.fromJson(
            _asObject(json['pendingCardEffect'], 'pendingCardEffect'),
          );
    final pendingCornered = json['pendingCornered'] == null
        ? null
        : PendingCornered.fromJson(
            _asObject(json['pendingCornered'], 'pendingCornered'),
          );
    final pendingSecretFinish = json['pendingSecretFinish'] == null
        ? null
        : PendingSecretFinish.fromJson(
            _asObject(json['pendingSecretFinish'], 'pendingSecretFinish'),
          );
    final winner = json['winner'] == null
        ? null
        : MatchOutcome.fromJson(_asObject(json['winner'], 'winner'));
    final deadline = _nullableString(json, 'deadlineUtc');
    if (deadline != null && DateTime.tryParse(deadline) == null) {
      throw const FormatException('Invalid deadlineUtc');
    }
    final phaseValue = turnPhase.single;
    if ((phaseValue == TurnPhase.awaitingReaction) != (pendingAttack != null) ||
        (phaseValue == TurnPhase.awaitingCardEffect) !=
            (pendingCardEffect != null) ||
        (phaseValue == TurnPhase.awaitingAccusation ||
                phaseValue == TurnPhase.awaitingSecretFinish ||
                phaseValue == TurnPhase.awaitingLastChance) !=
            (pendingCornered != null) ||
        (phaseValue == TurnPhase.awaitingSecretFinish) !=
            (pendingSecretFinish != null) ||
        (phaseValue == TurnPhase.finished ||
                phaseValue == TurnPhase.cancelled) !=
            (winner != null)) {
      throw const FormatException(
        'Pending state does not match the current phase',
      );
    }
    return MatchState(
      matchId: _nonemptyString(json, 'matchId'),
      phase: turnPhase.single,
      version: version,
      actionsRemaining: actions,
      attacksUsedThisTurn: attacks,
      suspicionAwardedForDamageThisTurn: _value<bool>(
        json,
        'suspicionAwardedForDamageThisTurn',
      ),
      investigationTargetsThisTurn:
          json.containsKey('investigationTargetsThisTurn')
          ? _strings(json, 'investigationTargetsThisTurn')
          : [],
      currentPlayerId: _nullableString(json, 'currentPlayerId'),
      seatOrder: seats,
      players: players,
      drawPile: _strings(json, 'drawPile'),
      discardPile: _strings(json, 'discardPile'),
      publicActionHistory: history,
      activeEffects: effects,
      accusationUsed: _strings(json, 'accusationUsed'),
      pendingAttack: pendingAttack,
      pendingCardEffect: pendingCardEffect,
      pendingCornered: pendingCornered,
      pendingSecretFinish: pendingSecretFinish,
      deadlineUtc: deadline,
      winner: winner,
    );
  }

  MatchState copyWith({
    TurnPhase? phase,
    int? version,
    int? actionsRemaining,
    int? attacksUsedThisTurn,
    bool? suspicionAwardedForDamageThisTurn,
    List<String>? investigationTargetsThisTurn,
    String? currentPlayerId,
    Map<String, PlayerState>? players,
    List<String>? drawPile,
    List<String>? discardPile,
    List<String>? accusationUsed,
    List<PublicAction>? publicActionHistory,
    List<SafePlaceEffect>? activeEffects,
    PendingAttack? pendingAttack,
    bool clearPendingAttack = false,
    PendingCardEffect? pendingCardEffect,
    bool clearPendingCardEffect = false,
    PendingCornered? pendingCornered,
    bool clearPendingCornered = false,
    PendingSecretFinish? pendingSecretFinish,
    bool clearPendingSecretFinish = false,
    String? deadlineUtc,
    bool clearDeadlineUtc = false,
    bool clearCurrentPlayerId = false,
    MatchOutcome? winner,
  }) => MatchState(
    matchId: matchId,
    phase: phase ?? this.phase,
    version: version ?? this.version,
    actionsRemaining: actionsRemaining ?? this.actionsRemaining,
    attacksUsedThisTurn: attacksUsedThisTurn ?? this.attacksUsedThisTurn,
    suspicionAwardedForDamageThisTurn:
        suspicionAwardedForDamageThisTurn ??
        this.suspicionAwardedForDamageThisTurn,
    investigationTargetsThisTurn:
        investigationTargetsThisTurn ?? this.investigationTargetsThisTurn,
    currentPlayerId: clearCurrentPlayerId
        ? null
        : currentPlayerId ?? this.currentPlayerId,
    seatOrder: seatOrder,
    players: players ?? this.players,
    drawPile: drawPile ?? this.drawPile,
    discardPile: discardPile ?? this.discardPile,
    publicActionHistory: publicActionHistory ?? this.publicActionHistory,
    activeEffects: activeEffects ?? this.activeEffects,
    accusationUsed: accusationUsed ?? this.accusationUsed,
    pendingAttack: clearPendingAttack
        ? null
        : pendingAttack ?? this.pendingAttack,
    pendingCardEffect: clearPendingCardEffect
        ? null
        : pendingCardEffect ?? this.pendingCardEffect,
    pendingCornered: clearPendingCornered
        ? null
        : pendingCornered ?? this.pendingCornered,
    pendingSecretFinish: clearPendingSecretFinish
        ? null
        : pendingSecretFinish ?? this.pendingSecretFinish,
    deadlineUtc: clearDeadlineUtc ? null : deadlineUtc ?? this.deadlineUtc,
    winner: winner ?? this.winner,
  );

  Map<String, Object?> toJson() => {
    'matchId': matchId,
    'rulesVersion': rulesVersion,
    'catalogVersion': catalogVersion,
    'phase': phase.wireValue,
    'version': version,
    'actionsRemaining': actionsRemaining,
    'attacksUsedThisTurn': attacksUsedThisTurn,
    'suspicionAwardedForDamageThisTurn': suspicionAwardedForDamageThisTurn,
    'investigationTargetsThisTurn': investigationTargetsThisTurn,
    'currentPlayerId': currentPlayerId,
    'pendingAttack': pendingAttack?.toJson(),
    'pendingCardEffect': pendingCardEffect?.toJson(),
    'pendingCornered': pendingCornered?.toJson(),
    'pendingSecretFinish': pendingSecretFinish?.toJson(),
    'seatOrder': seatOrder,
    'deadlineUtc': deadlineUtc,
    'players': players.map((key, value) => MapEntry(key, value.toJson())),
    'drawPile': drawPile,
    'discardPile': discardPile,
    'publicActionHistory': publicActionHistory
        .map((value) => value.toJson())
        .toList(),
    'activeEffects': activeEffects.map((value) => value.toJson()).toList(),
    'accusationUsed': accusationUsed,
    'winner': winner?.toJson(),
  };
}

T _value<T>(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! T) throw FormatException('Invalid field: $key');
  return value;
}

void _checkKeys(
  Map<String, Object?> json,
  Set<String> required, {
  Set<String> optional = const {},
}) {
  if (!json.keys.toSet().containsAll(required) ||
      json.keys.toSet().difference({...required, ...optional}).isNotEmpty) {
    throw const FormatException('Missing or unknown state fields');
  }
}

String _nonemptyString(Map<String, Object?> json, String key) {
  final value = _value<String>(json, key);
  if (value.isEmpty) throw FormatException('Empty field: $key');
  return value;
}

String? _nullableString(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value != null && value is! String) {
    throw FormatException('Invalid field: $key');
  }
  return value as String?;
}

Map<String, Object?> _asObject(Object? value, String key) {
  if (value is! Map<String, Object?>) {
    throw FormatException('Invalid object: $key');
  }
  return value;
}

Map<String, Object?> _object(Map<String, Object?> json, String key) =>
    _asObject(json[key], key);

List<Object?> _list(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! List) throw FormatException('Invalid list: $key');
  return value;
}

List<String> _strings(Map<String, Object?> json, String key) {
  final values = _list(json, key);
  if (values.any((value) => value is! String)) {
    throw FormatException('Invalid string list: $key');
  }
  return values.cast<String>();
}

T _enumByName<T extends Enum>(List<T> values, String name, String key) {
  for (final value in values) {
    if (value.name == name) return value;
  }
  throw FormatException('Invalid $key: $name');
}
