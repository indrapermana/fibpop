import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { describe, expect, it } from 'vitest';

import { respondToAttack, startAttack, playSafePlace } from '../src/attacks.js';
import {
  playCardSwap,
  playCatchYourBreath,
  playCleanSlate,
  playFirstAid,
  playPatchUp,
  playPointFingers,
  playSpotlight,
  playStirThePot,
  respondToCardEffectDiscard,
} from '../src/card-effects.js';
import { parseCardCatalog } from '../src/card-catalog.js';
import { getCardDesignId } from '../src/card-instance.js';
import {
  expireAccusationOffer,
  expireLastChanceWindow,
  expireSecretFinishWindow,
  passLastChance,
  playLastChance,
  respondToAccusation,
  submitSecretFinishChoice,
} from '../src/cornered.js';
import { handlePlayerDeparture } from '../src/departures.js';
import { EngineError } from '../src/errors.js';
import {
  recordTransition,
  replayTransitions,
  type StateTransitionEvent,
} from '../src/events.js';
import {
  scenarioSuiteSchema,
  type ScenarioCommand,
} from '../src/golden-fixture.js';
import { basicObserve, playInvestigation } from '../src/investigations.js';
import { projectPlayerState, projectPublicState } from '../src/projections.js';
import { matchStateSchema, type MatchState } from '../src/state.js';
import { beginTurn, endTurn } from '../src/turns.js';

const load = (relativePath: string): unknown =>
  JSON.parse(
    readFileSync(fileURLToPath(new URL(relativePath, import.meta.url)), 'utf8'),
  );

const suite = scenarioSuiteSchema.parse(
  load('../../../shared/fixtures/m1-gameplay-scenarios.json'),
);
const catalog = parseCardCatalog(load('../../../shared/card_catalog_v1.json'));

function randomSource(values: number[]) {
  let index = 0;
  return {
    next: () => {
      const value = values[index++];
      if (value === undefined)
        throw new Error('Fixture random sequence exhausted');
      return value;
    },
  };
}

function requiredTarget(
  command: Extract<ScenarioCommand, { type: 'PLAY_CARD' }>,
): string {
  if (!command.target) throw new Error(`Missing target for ${command.card}`);
  return command.target;
}

function execute(
  state: MatchState,
  command: ScenarioCommand,
): { state: MatchState; result?: object } {
  switch (command.type) {
    case 'ATTACK':
      return {
        state: startAttack(state, command.actor, command.target, command.card),
      };
    case 'ATTACK_RESPONSE':
      return {
        state: respondToAttack(
          state,
          command.actor,
          command.response,
          command.nowMs,
        ),
      };
    case 'INVESTIGATE': {
      const { state: next, ...result } = playInvestigation(state, {
        actorPlayerId: command.actor,
        targetPlayerId: command.target,
        cardInstanceId: command.card,
        random: randomSource(command.randomSequence),
        ...(command.defense ? { defense: command.defense } : {}),
      });
      return { state: next, result };
    }
    case 'PLAY_CARD': {
      const { actor, card } = command;
      const random = randomSource(command.randomSequence);
      switch (getCardDesignId(card)) {
        case 'card_13':
          return {
            state: playPointFingers(
              state,
              actor,
              requiredTarget(command),
              card,
            ),
          };
        case 'card_14':
          return { state: playCleanSlate(state, actor, card) };
        case 'card_15':
          if (!command.targets) throw new Error('Missing Stir the Pot targets');
          return { state: playStirThePot(state, actor, command.targets, card) };
        case 'card_16': {
          const { state: next, ...result } = playCardSwap(
            state,
            actor,
            requiredTarget(command),
            card,
            random,
          );
          return { state: next, result };
        }
        case 'card_17':
          return {
            state: playFirstAid(state, actor, requiredTarget(command), card),
          };
        case 'card_18': {
          const { state: next, ...result } = playCatchYourBreath(
            state,
            actor,
            card,
            random,
          );
          return { state: next, result };
        }
        case 'card_20':
          return { state: playPatchUp(state, actor, card) };
        case 'card_21':
          return {
            state: playSafePlace(state, actor, requiredTarget(command), card),
          };
        case 'card_23': {
          const { state: next, ...result } = playSpotlight(
            state,
            actor,
            card,
            random,
          );
          return { state: next, result };
        }
        default:
          throw new Error(`Unsupported fixture action card ${card}`);
      }
    }
    case 'DISCARD': {
      const { state: next, ...result } = respondToCardEffectDiscard(
        state,
        command.actor,
        command.card,
      );
      return { state: next, result };
    }
    case 'BASIC_OBSERVE': {
      const { state: next, ...result } = basicObserve(
        state,
        command.actor,
        command.target,
      );
      return { state: next, result };
    }
    case 'ACCUSE':
      return {
        state: respondToAccusation(
          state,
          command.actor,
          { kind: command.response },
          command.nowMs,
        ),
      };
    case 'EXPIRE_ACCUSATION':
      return { state: expireAccusationOffer(state, command.nowMs) };
    case 'SECRET_CHOICE':
      return {
        state: submitSecretFinishChoice(
          state,
          command.actor,
          command.choice,
          command.nowMs,
        ),
      };
    case 'EXPIRE_SECRET':
      return { state: expireSecretFinishWindow(state, command.nowMs) };
    case 'PLAY_LAST_CHANCE':
      return {
        state: playLastChance(
          state,
          command.actor,
          command.card,
          command.nowMs,
        ),
      };
    case 'PASS_LAST_CHANCE':
      return { state: passLastChance(state, command.actor, command.nowMs) };
    case 'EXPIRE_LAST_CHANCE':
      return { state: expireLastChanceWindow(state, command.nowMs) };
    case 'DEPARTURE':
      return {
        state: handlePlayerDeparture(state, command.actor, command.departure),
      };
    case 'END_TURN':
      return { state: endTurn(state, command.discards) };
    case 'BEGIN_TURN':
      return { state: beginTurn(state, randomSource(command.randomSequence)) };
  }
}

function initialState(
  overrides: (typeof suite.scenarios)[number]['initialState'],
): MatchState {
  const players = { ...suite.baseState.players };
  for (const [id, player] of Object.entries(overrides.players ?? {})) {
    if (!players[id]) throw new Error(`Unknown fixture player ${id}`);
    players[id] = { ...players[id], ...player };
  }
  return matchStateSchema.parse({ ...suite.baseState, ...overrides, players });
}

describe('shared gameplay scenarios', () => {
  it.each(suite.scenarios)('$name', (scenario) => {
    let state = initialState(scenario.initialState);
    const initial = structuredClone(state);
    const events: StateTransitionEvent[] = [];
    for (const step of scenario.steps) {
      const before = structuredClone(state);
      if (step.expectedError) {
        let error: unknown;
        try {
          execute(state, step.command);
        } catch (caught) {
          error = caught;
        }
        expect(error).toBeInstanceOf(EngineError);
        expect(error).toMatchObject({ code: step.expectedError });
        expect(state).toEqual(before);
        continue;
      }
      const outcome = execute(state, step.command);
      expect(state).toEqual(before);
      if (step.expectedResult)
        expect(outcome.result).toMatchObject(step.expectedResult);
      if (outcome.state.version === state.version) {
        expect(outcome.state).toEqual(state);
      } else {
        events.push(recordTransition(state, outcome.state));
      }
      state = outcome.state;
      expect(
        replayTransitions(initial, JSON.parse(JSON.stringify(events))),
      ).toEqual(state);
      if (step.expectedPublic || step.absentPublicPaths) {
        const view = projectPublicState(state);
        if (step.expectedPublic)
          expect(view).toMatchObject(step.expectedPublic);
        for (const path of step.absentPublicPaths ?? []) {
          expect(view).not.toHaveProperty(path);
        }
      }
      for (const [playerId, expected] of Object.entries(
        step.expectedPrivate ?? {},
      )) {
        expect(projectPlayerState(state, playerId)).toMatchObject(expected);
      }
    }
    expect(state).toMatchObject(scenario.expectedState);
    expect(
      replayTransitions(initial, JSON.parse(JSON.stringify(events))),
    ).toEqual(state);
  });

  it('executes all 24 catalog designs in successful scenarios', () => {
    const used = new Set<string>();
    for (const scenario of suite.scenarios) {
      for (const step of scenario.steps) {
        if (step.expectedError) continue;
        const command = step.command;
        if (
          command.type === 'ATTACK' ||
          command.type === 'INVESTIGATE' ||
          command.type === 'PLAY_CARD' ||
          command.type === 'PLAY_LAST_CHANCE'
        ) {
          const card = getCardDesignId(command.card);
          if (card) used.add(card);
        }
        if (
          command.type === 'ATTACK_RESPONSE' &&
          command.response.kind !== 'pass'
        ) {
          const card = getCardDesignId(command.response.cardInstanceId);
          if (card) used.add(card);
        }
        if (
          command.type === 'INVESTIGATE' &&
          command.defense?.kind === 'misdirection'
        ) {
          const card = getCardDesignId(command.defense.cardInstanceId);
          if (card) used.add(card);
        }
      }
    }
    expect([...used].sort()).toEqual(
      catalog.cards.map((card) => card.id).sort(),
    );
  });

  it('rejects duplicate scenario names and malformed commands', () => {
    const scenario = suite.scenarios[0];
    expect(
      scenarioSuiteSchema.safeParse({
        ...suite,
        scenarios: [scenario, scenario],
      }).success,
    ).toBe(false);
    expect(
      scenarioSuiteSchema.safeParse({
        ...suite,
        scenarios: [
          {
            ...scenario,
            steps: [{ command: { type: 'BEGIN_TURN', randomSequence: [1] } }],
          },
        ],
      }).success,
    ).toBe(false);
  });
});
