import 'dart:convert';

import 'game_state.dart';
import 'turns.dart';

const _eventFields = {
  'type',
  'matchId',
  'previousVersion',
  'version',
  'changes',
};
const _stateChangeFields = {
  'phase',
  'actionsRemaining',
  'attacksUsedThisTurn',
  'suspicionAwardedForDamageThisTurn',
  'investigationTargetsThisTurn',
  'currentPlayerId',
  'pendingAttack',
  'pendingCardEffect',
  'pendingCornered',
  'pendingSecretFinish',
  'seatOrder',
  'deadlineUtc',
  'players',
  'drawPile',
  'discardPile',
  'publicActionHistory',
  'activeEffects',
  'accusationUsed',
  'winner',
};

class _ParsedTransition {
  const _ParsedTransition({
    required this.matchId,
    required this.previousVersion,
    required this.version,
    required this.changes,
  });

  final String matchId;
  final int previousVersion;
  final int version;
  final Map<String, Object?> changes;
}

Map<String, Object?> _jsonObject(Object? value, String name) {
  if (value is! Map || value.keys.any((key) => key is! String)) {
    throw EngineException('INVALID_EVENT', 'Invalid state transition $name');
  }
  return value.cast<String, Object?>();
}

Map<String, Object?> _detachedObject(Map<String, Object?> value) =>
    (jsonDecode(jsonEncode(value)) as Map).cast<String, Object?>();

_ParsedTransition _parseTransition(Object? input) {
  final event = _jsonObject(input, 'event');
  if (event.keys.toSet().difference(_eventFields).isNotEmpty ||
      !_eventFields.every(event.containsKey) ||
      event['type'] != 'STATE_TRANSITION' ||
      event['matchId'] is! String ||
      (event['matchId'] as String).isEmpty ||
      event['previousVersion'] is! int ||
      event['version'] is! int) {
    throw const EngineException(
      'INVALID_EVENT',
      'Invalid state transition event',
    );
  }
  final previousVersion = event['previousVersion'] as int;
  final version = event['version'] as int;
  if (previousVersion < 0 || version != previousVersion + 1) {
    throw const EngineException(
      'INVALID_EVENT',
      'A transition must advance exactly one version',
    );
  }
  final changes = _jsonObject(event['changes'], 'changes');
  if (changes.keys.toSet().difference(_stateChangeFields).isNotEmpty) {
    throw const EngineException(
      'INVALID_EVENT',
      'Invalid state transition event',
    );
  }
  return _ParsedTransition(
    matchId: event['matchId'] as String,
    previousVersion: previousVersion,
    version: version,
    changes: _detachedObject(changes),
  );
}

Map<String, Object?> recordTransition(MatchState previous, MatchState next) {
  final before = MatchState.fromJson(previous.toJson()).toJson();
  final after = MatchState.fromJson(next.toJson()).toJson();
  if (previous.matchId != next.matchId ||
      previous.version + 1 != next.version) {
    throw const EngineException(
      'INVALID_EVENT',
      'Transition identity or version does not match',
    );
  }
  final changes = <String, Object?>{};
  for (final key in _stateChangeFields) {
    if (jsonEncode(before[key]) != jsonEncode(after[key])) {
      changes[key] = after[key];
    }
  }
  return _detachedObject({
    'type': 'STATE_TRANSITION',
    'matchId': previous.matchId,
    'previousVersion': previous.version,
    'version': next.version,
    'changes': changes,
  });
}

MatchState applyTransition(MatchState state, Object? input) {
  final event = _parseTransition(input);
  if (state.matchId != event.matchId ||
      state.version != event.previousVersion) {
    throw const EngineException(
      'INVALID_EVENT',
      'State transition is stale or belongs to another match',
    );
  }
  final current = MatchState.fromJson(state.toJson()).toJson();
  try {
    return MatchState.fromJson({
      ...current,
      ...event.changes,
      'version': event.version,
    });
  } on FormatException {
    throw const EngineException(
      'INVALID_EVENT',
      'Invalid state transition event',
    );
  } on UnsupportedError {
    throw const EngineException(
      'INVALID_EVENT',
      'Invalid state transition event',
    );
  }
}

MatchState replayTransitions(MatchState initialState, List<Object?> events) =>
    events.fold(MatchState.fromJson(initialState.toJson()), applyTransition);
