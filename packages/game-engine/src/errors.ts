export const engineErrorCodes = [
  'INVALID_COMMAND',
  'INVALID_PHASE',
  'NOT_YOUR_TURN',
  'NOT_ELIGIBLE',
  'INVALID_DISCARD_COUNT',
  'INVALID_DISCARD',
  'INVALID_ACTION',
  'INVALID_ACTION_COST',
  'NO_ACTIONS_REMAIN',
  'ATTACK_LIMIT',
  'INVALID_TARGET',
  'INVALID_PLAYER',
  'INVALID_SUSPICION_CHANGE',
  'INVALID_ACTION_PHASE',
  'DUPLICATE_ATTACK_RECORD',
  'INVALID_CARD',
  'INVALID_INSPECTION_DEFENSE',
  'INVALID_REACTION',
  'SAFE_PLACE_ALREADY_ACTIVE',
] as const;

export type EngineErrorCode = (typeof engineErrorCodes)[number];

export class EngineError extends Error {
  constructor(
    readonly code: EngineErrorCode,
    message: string,
  ) {
    super(message);
    this.name = 'EngineError';
  }
}

export type EngineResult<T> =
  | { ok: true; value: T }
  | { ok: false; error: { code: EngineErrorCode; message: string } };

export function failed<T = never>(
  code: EngineErrorCode,
  message: string,
): EngineResult<T> {
  return { ok: false, error: { code, message } };
}
