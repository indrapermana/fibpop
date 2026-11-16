import { describe, expect, it } from 'vitest';

import app from '../src/index.js';

describe('GET /api/health', () => {
  it('returns the active rules and protocol versions', async () => {
    const response = await app.request('/api/health');

    expect(response.status).toBe(200);
    await expect(response.json()).resolves.toEqual({
      status: 'ok',
      rulesVersion: '2.1.0',
      catalogVersion: '1.0.0',
      protocolVersion: 2,
    });
  });
});
