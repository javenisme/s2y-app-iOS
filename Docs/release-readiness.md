# iOS production release readiness

This checklist separates repository evidence from external production evidence.
Passing the repository preflight does not prove that sign-in, App Store signing,
or a production Omer request succeeds.

## Automated repository preflight

Run:

```sh
Scripts/validate_release_configuration.sh
```

The deployment workflow runs the same check before build and signing. It verifies
without printing credential values that:

- the Xcode application target, Fastlane, and Firebase iOS plist use
  `us.s2y.s2y-ios`;
- the Firebase iOS plist and Firebase CLI default use `s2y-mobile-app`;
- Info.plist and the Omer service fallback use `https://chat.s2y.us`;
- retired `chat-bak.s2y.us` and embedded test-account material do not remain in
  executable/configuration paths.

The workflow also runs `Scripts/check_public_production_endpoints.sh`. It verifies
only that the public login page responds and that an unauthenticated Omer mobile
request is rejected. It never follows an authenticated flow or prints response
headers, cookies, tokens, or bodies.

The repository previously contained an embedded development-account password.
It has been removed from the current tree. Any account that ever used that value
must be treated as compromised and rotated or deleted because Git history is not
a secret store.

## External production evidence

Record these results for every production candidate:

Use [`release-validation.md`](release-validation.md) as the redacted evidence record.

| Check | Required evidence |
|---|---|
| Firebase sign-in | Test account completes the intended provider flow and receives a Firebase UID |
| Omer authentication | `chat.s2y.us` accepts a fresh Firebase ID token and rejects missing/invalid tokens |
| Consent enforcement | Each health scope is absent by default, appears only after grant, and stops after revoke |
| Omer accounting | The authenticated request is attributed to the correct user, entitlement, and token ledger |
| Data lifecycle | Conversation deletion and account-boundary messaging match actual production behavior |
| Signing | Archive uses the approved App ID, distribution certificate, profile, and entitlements |
| TestFlight | Installed build launches, signs in, chats, displays unavailable states, and can be rolled back |

Do not attach tokens, plist contents, health records, or personal messages to the
release record. Use request IDs, redacted timestamps, build numbers, and pass/fail
observations.

## Explicitly not proven by CI

- Google/Firebase browser callback configuration;
- Apple Foundation Models on an eligible iPhone;
- App Store Connect credentials and review acceptance;
- real S2Y device firmware identity and session behavior;
- production Omer database contents or billing correctness.
