# Portal declaration recommendations — publisher review required

These are recommendations for the inspected 1.0.0+1 source and locked dependencies, not submitted legal declarations. Confirm them against the final signed binary and all other currently distributed variants.

## Google Play
- Category: Music & Audio. Suggested tags are candidates only; select those actually offered in Console.
- App contains ads: No, based on inspected code/dependencies.
- Data Safety: recommend no developer collection and no non-exempt sharing for this version. Microphone samples, derived notes, preferences, and compositions are processed/stored on-device. Explicit OS sharing of a score is user initiated. Review Google's user-initiated transfer exception before answering. Permission to record audio does not itself mean developer collection.
- No app account or account creation; account-deletion URL requirement should not apply. Support/data removal instructions are on the support page.
- Do not claim an independent security audit, encryption-in-transit guarantee, or deletion of third-party exports. No application transmission exists to evaluate.
- Target audience, children's/Families participation, countries, pricing, content rights, and IARC answers require the publisher's choices. Do not infer “designed for children” from beginner music functionality.
- Content rating: no built-in violence, gambling, sexual content, profanity, drugs, purchases, public posting, chat, or unrestricted browser. Local lyrics and imported scores are private user content, not a public UGC service. Answer the current questionnaire accurately; Console determines the rating.
- Confirm any new developer-account testing and verification requirements in Console, including closed-testing eligibility, before production access.

## Apple
- App Privacy: recommend “Data Not Collected” for the inspected build. Apple's definition excludes data processed only on-device. No tracking, advertising identifier, analytics, or linked identity was found. Review final bundled SDKs and any separate support practices before confirming.
- Microphone: required only for listening features; the purpose string explains note detection. No ATT prompt is appropriate for this code because tracking is absent.
- Age rating: no in-app age assurance or parental controls, no messaging/public sharing community, ads, in-app purchases, unrestricted web, medical/treatment guidance, gambling, sexual material, violence, or other listed mature content. Private score lyrics/imports are user supplied. Apple determines the rating from the current regional questionnaire; do not manually promise a rating.
- Review contact first/last name and telephone number must be entered by the owner. Existing public support email: ftrevino@yahoo.com. Confirm rights to the artwork and all bundled materials, pricing, territorial availability, target audience, and export-compliance answers.
- Encryption: archive/compression and local audio do not alone answer export compliance. Review the final binary/Flutter engine and use Apple's questionnaire before adding ITSAppUsesNonExemptEncryption. No automatic declaration was added.

## URLs after approved website publication
Support: https://frtrev.github.io/sheet-music-rookie/support/
Privacy: https://frtrev.github.io/sheet-music-rookie/privacy-policy/
Marketing: https://frtrev.github.io/sheet-music-rookie/

The pages are prepared locally. Do not enter these URLs as live policy links until the website changes have been approved, deployed, and checked over HTTPS.

References checked 6 November 2026:
- https://developer.apple.com/app-store/app-privacy-details/
- https://support.google.com/googleplay/android-developer/answer/10787469?hl=en
- https://developer.apple.com/help/app-store-connect/manage-app-information/set-an-app-age-rating/
