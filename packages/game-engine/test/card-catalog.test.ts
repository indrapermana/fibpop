import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

import { describe, expect, it } from 'vitest';

import { parseCardCatalog } from '../src/card-catalog.js';

const catalogPath = fileURLToPath(
  new URL('../../../shared/card_catalog_v1.json', import.meta.url),
);
const sourceCatalog: unknown = JSON.parse(readFileSync(catalogPath, 'utf8'));

describe('source card catalog', () => {
  it('contains 24 unique designs and exactly 72 copies', () => {
    const catalog = parseCardCatalog(sourceCatalog);

    expect(catalog.cards).toHaveLength(24);
    expect(new Set(catalog.cards.map((card) => card.id)).size).toBe(24);
    expect(catalog.cards.reduce((total, card) => total + card.copies, 0)).toBe(
      72,
    );
  });

  it('rejects duplicate design IDs', () => {
    const catalog = parseCardCatalog(sourceCatalog);
    const duplicate = {
      ...catalog,
      cards: [...catalog.cards, catalog.cards[0]],
    };

    expect(() => parseCardCatalog(duplicate)).toThrow();
  });

  it('rejects an incorrect total copy count', () => {
    const catalog = parseCardCatalog(sourceCatalog);
    const incorrectTotal = {
      ...catalog,
      cards: catalog.cards.map((card, index) =>
        index === 0 ? { ...card, copies: card.copies + 1 } : card,
      ),
    };

    expect(() => parseCardCatalog(incorrectTotal)).toThrow(
      /Expected 72 total card copies/,
    );
  });
});
