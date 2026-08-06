# Remaining work (as of 2026-08-06)

What's left after this session's auth + drive-history + backend-split work.
Everything not listed here is done and verified — see `HANDOFF.md` for the
full narrative and reasoning if you need the "why."

## Live right now

- Cloud Run `roam-backend` — difficulty-only, no DB, no Clerk. Deployed.
- Render `roam-data-api-n2sw` — accounts, drive history, Clerk-verified.
  Deployed, migrated, `CLERK_SECRET_KEY` set.
- Render `roam-db-n2sw` — Postgres, wired to the data API. Available.
- iOS — Clerk prebuilt auth, host routing (difficulty vs. data), Apple
  Sign-In capability removed to match the Clerk dashboard. Builds clean.

## Still to do

- [ ] **Rotate `CLERK_SECRET_KEY`.** The key in use was pasted into a chat
      transcript. Roll it in Clerk's dashboard, then update it in
      `backend/.env.local` and on the `roam-data-api-n2sw` service.
- [ ] **Register the native app in Clerk** (Configure → Native applications):
      Bundle ID `com.akhil.roam`, App ID Prefix `6RT6KBS4G9`. No API exposes
      whether this is already done — check the dashboard directly.
- [ ] **Apple Developer portal:** confirm Associated Domains is enabled on
      App ID `com.akhil.roam` with entry
      `webcredentials:capable-swan-35.clerk.accounts.dev` (still needed —
      only the Sign in with Apple capability was dropped, not the domain).
      Refresh provisioning profiles after any change here.
- [ ] **Swap Google OAuth off Clerk's shared dev credentials** before
      production — the instance is currently `test_mode: true`.
- [ ] **Delete or clean up leftovers in Render:** the old manually-created
      `roam-db` (suspended, not deleted) is no longer needed.
- [ ] **End-to-end check on a real device/simulator:** sign up through
      `AuthView` → confirm the user appears in Clerk's Users list → record a
      drive of 30+ seconds → delete and reinstall the app → sign in → confirm
      the drive comes back. This is the only real proof sync works.
- [ ] **Fix drive-deletion sync.** `DriveHistorySyncService` merges local and
      server drives as a union and never calls `DELETE /api/drives/:id`
      (which the backend already supports). Delete a drive on the phone and
      it comes back on the next sync.
- [ ] **`README.md` is stale** — still documents Render as a single combined
      backend deploy target and references `JWT_SECRET`. Doesn't match the
      split-backend + Clerk reality anymore.
- [ ] Re-check `ios/tests/SharedRouteImportChecks.swift` for flakiness — it
      failed once this session on an unrelated run with no source changes,
      then passed repeatedly after.
