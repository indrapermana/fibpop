# FIBPOP — Privacy, Terms & Store Release Checklist

**This is a planning checklist, not legally approved Terms or Privacy Policy.** Final notices must reflect *actual SDKs, hosting regions, data categories, retention, recipients and account flows*. Review with Indonesian legal/privacy counsel when going public, including UU No. 27/2022 (personal data protection) and the rules of each target market.

## Minimum-data design

- Offline: gameplay works without login or internet. Local saved state and language/settings; describe device-side storage accurately.
- Online: guest pseudonymous player ID, session credentials, display name (if any), match participation/history, abuse reports, purchases/entitlements if introduced, essential security logs, and network identifiers processed by infrastructure.
- Ads/analytics added later may collect device identifiers and usage/consent signals: declare each SDK's actual practices before deployment. Avoid contacts, location, camera, microphone and freeform chat unless necessary.
- Private game state (role, hand, evidence) must not enter public analytics or URL query strings.

## Privacy policy requirements

Name of operator and contact channel; categories collected and reasons; lawful basis/consent where required; processors and cross-border handling; retention periods; security measures; user access/correction/deletion rights; how to revoke ad consent; children's privacy; policy version/date; how future changes are notified. Provide Indonesian and English versions. Publish stable reachable HTTPS URL (suggest path on company's site). Do not invent a company contact email; configure a real monitored address.

## Terms of Service outline

Eligibility/age and parent rules; guest and account credential responsibility; game rules and fair-play/anti-cheat; no abuse or impersonation; virtual cosmetics license rather than ownership; purchase, refunds and store priority; account suspension and appeals; service availability; intellectual property; third-party links and ads; limitations subject to consumer law; dispute resolution, governing law and customer-support contact. Provide Indonesian/English versions with review before publication.

## Google Play

- Register developer account (US$25 one-time fee as published); organization verification if publishing under PT.
- Complete Data safety and content rating accurately, target audience/ads declarations, privacy-policy URL, store listing, app access for reviewers, appropriate advertising labeling and IAP billing.
- If allowing account creation, provide account deletion both inside app and via a public web URL; retain only legally justified data where necessary and disclose exceptions.
- New personal developer accounts created after Nov 13, 2023 generally require a qualifying closed test with at least 12 testers opted in for 14 continuous days before applying for production. Confirm account-specific rules.
- Test new Android target API, permissions, SDK requirements, Play integrity and signing at release date.

## Apple App Store

- Developer Program US$99 per year as published (local pricing may differ); organization enrollment may require verification.
- Include accurate App Privacy disclosures and in-app privacy-policy access.
- If account creation is supported, provide in-app account deletion; guest play should remain possible where appropriate.
- Use Apple In-App Purchase where required for digital cosmetics; implement restore and receipt verification; test with StoreKit sandbox/TestFlight.
- Provide review account/demo or playable guest mode, screenshot assets, complete support links, accurate age rating and reviewer notes.
- If adding arbitrary usernames, freeform chat or player-created content, build report/block/moderation features before release. Prefer preset emotes in MVP.

## IP/brand/asset clearance

Search DJKI/WIPO/app-stores for FIBPOP and confusingly similar names. Source original text, card artwork, SFX, fonts and UI assets with commercial licenses documented. Avoid suggesting formal affiliation with third-party games. The tabletop rules are original work in progress but require independent IP review before commercialization.

## Official reference URLs (checked Nov 2026)

- https://support.google.com/googleplay/android-developer/answer/6112435
- https://support.google.com/googleplay/android-developer/answer/14151465
- https://support.google.com/googleplay/android-developer/answer/18265346
- https://developer.apple.com/help/account/membership/program-enrollment
- https://developer.apple.com/app-store/review/guidelines/
- https://pdki-indonesia.dgip.go.id/
- https://branddb.wipo.int/
