# FIBPOP — Monetization & Business Plan

**Commercial goal:** An accessible free-to-play game that can finance its own infrastructure and create sustainable profit for planned publisher PT Indesya Karya Digital. All numerical values below are **hypotheses**, not forecasts.

## Monetization sequence

1. Closed beta: no ads/IAP; collect playtime, retention, match-completion and referral metrics with lawful consent where needed.
2. Initial launch: optional *rewarded ads after matches* granting cosmetic-only currency; optionally one capped post-match interstitial per ~3 matches, minimum cooldown 5 minutes, disabled for Plus owners.
3. When stable: direct-purchase cosmetics and `FIBPOP Plus` one-time ad removal with cosmetic bundle.
4. Only after retention proven: seasonal cosmetic collections; no paid gameplay advantages or randomized loot boxes.

## Starter catalog (price proposals, not committed SKUs)

| Product | Indonesia candidate price | Notes |
|---|---:|---|
| Card back | Rp9,000–19,000 | Visual only |
| Avatar frame | Rp5,000–15,000 | Visual only |
| Emote pack | Rp9,000–19,000 | Preset emotes only |
| Victory effect | Rp15,000–29,000 | Visual only |
| FIBPOP Plus | Rp49,000 one time | Remove automated interstitials + cosmetic bundle |

No paid health, Evidence, rerolls, attacks, superior bots, or greater win odds. Define cosmetic currency earned without ads for Plus users; purchased currency requires dedicated accounting and store policy review.

## Advertising rules

- No ads during a live turn, defense, accusation, or lobby ready check.
- Rewarded ad opt-in only, post-match, rewarded only after verified completion callback; idempotent reward ledger.
- Ads optional in offline mode; offline game must function with SDK unavailable.
- No targeted ads to child users without required safeguards; determine intended age audience prior to SDK selection; implement region-specific consent choices and opt-outs.

## Unit economics formulas

- `monthly_ad_revenue = DAU × ads_per_DAU_day × 30 × eCPM / 1000`.
- `gross_IAP = monthly_purchase_count × mean_price`.
- `net_IAP ≈ gross_IAP × (1 − effective_store_fee − refunds − applicable_adjustments)`.
- `monthly_contribution = net_ad_revenue + net_IAP − infrastructure − support − marketing − directly attributable costs`.

Example scenario (illustrative): 1,000 DAU × 1.5 ads/day × 30 ÷ 1,000 × $1 eCPM = **$45 gross ad revenue/month**, before adjustments. Example: 30 purchases × $2 = $60 gross IAP. With assumed 20% store fee: $48; combined $93 before hosting, marketing, support, taxes. Real regional eCPMs and conversion rates vary; do not call this a forecast.

## Infrastructure capacity rules

- Target $0 incremental backend spending for very low traffic within Cloudflare free quotas; cannot guarantee free early production.
- Meter DO requests, WebSocket messages, active duration, SQLite rows read/written/storage, Worker requests and egress. Free plans can hard-fail when limits exceeded.
- Before paid acquisition or major influencer release, establish usage alerts, adaptive queue admission and a paid-plan/scale budget. Keep a contingency reserve.
- Cost-per-completed-online-match should be measured, not inferred from installations. A popularity spike can incur cost before monetization catches up.

## Business KPIs and initial hypotheses

Retention D1/D7, average completed matches per DAU, fraction of invitations converted, quick-start queue fill %, crash-free sessions, server cost per match, ad opt-in %, ad eCPM, IAP conversion, average revenue per DAU, refunds, player reports. Set launch thresholds from beta data rather than assuming a sustainable DAU count.

## Payments and entitlements

Use the platform's required in-app billing for mobile digital items; implement server receipt verification, refund/revocation handling, restore purchases, account linking for cross-device purchases, cosmetic entitlement records and consistent audit logs. Do not silently transfer purchases between Android, iOS and web without platform policy review.

## Corporate finance & tax

Record revenue and costs separately under the FIBPOP product for PT Indesya Karya Digital. Reconcile store settlement statements, ad payouts, currency conversion, refunds and withholding taxes with the company's accountant. Corporate cash ≠ accounting profit; no owner distributions based solely on gross store revenue.
