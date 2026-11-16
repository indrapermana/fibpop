import { z } from 'zod';

const cardSchema = z
  .object({
    id: z.string().regex(/^card_\d{2}$/),
    category: z.enum([
      'attacks',
      'defense',
      'investigation',
      'manipulation',
      'recovery',
      'special',
    ]),
    name_en: z.string().min(1),
    copies: z.number().int().positive(),
    rules_text_en: z.string().min(1),
  })
  .strict();

export const cardCatalogSchema = z
  .object({
    catalog_version: z.string().regex(/^\d+\.\d+\.\d+$/),
    source: z.string().min(1),
    status: z.string().min(1),
    cards: z.array(cardSchema).length(24),
  })
  .strict()
  .superRefine((catalog, context) => {
    const seenIds = new Set<string>();
    let totalCopies = 0;

    catalog.cards.forEach((card, index) => {
      if (seenIds.has(card.id)) {
        context.addIssue({
          code: z.ZodIssueCode.custom,
          message: `Duplicate card design id: ${card.id}`,
          path: ['cards', index, 'id'],
        });
      }

      seenIds.add(card.id);
      totalCopies += card.copies;
    });

    if (totalCopies !== 72) {
      context.addIssue({
        code: z.ZodIssueCode.custom,
        message: `Expected 72 total card copies, received ${totalCopies}`,
        path: ['cards'],
      });
    }
  });

export type CardCatalog = z.infer<typeof cardCatalogSchema>;
export type CardDesign = CardCatalog['cards'][number];

export function parseCardCatalog(input: unknown): CardCatalog {
  return cardCatalogSchema.parse(input);
}
