import { readFileSync, readdirSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

import { describe, expect, it } from 'vitest';

import { goldenFixtureSchema } from '../src/golden-fixture.js';

const fixturesDirectory = fileURLToPath(
  new URL('../../../shared/fixtures/', import.meta.url),
);

describe('shared golden fixtures', () => {
  const fixtureFiles = readdirSync(fixturesDirectory).filter((file) =>
    file.endsWith('.json'),
  );

  it('contains at least one fixture', () => {
    expect(fixtureFiles.length).toBeGreaterThan(0);
  });

  it.each(fixtureFiles)('validates %s', (file) => {
    const fixture: unknown = JSON.parse(
      readFileSync(`${fixturesDirectory}/${file}`, 'utf8'),
    );

    expect(goldenFixtureSchema.parse(fixture).rulesVersion).toBe('2.1.0');
  });
});
