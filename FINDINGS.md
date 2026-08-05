# Roam — open audit findings

Audit date: 4 August 2026, against `19bf5a9`.

This file lists what was found and **deliberately not fixed**. Everything that
was fixed is in the working tree, not here.

Verification at time of writing: iOS `** BUILD SUCCEEDED **`; backend 103/103;
13 of 16 standalone Swift checks pass (the other 3 fail only under an ad-hoc
runner that is missing `Features/Home/RoutePlanningFormModel.swift` — they are
not broken, see "Test runner" at the bottom).

Accessibility and reduce-motion were excluded from scope throughout.

---

## Coverage warning — read first

One area remains unaudited. Absence of findings below is not evidence of
correctness:

- **Backend scoring arithmetic** (`backend/src/scoring/*.ts`) beyond the
  availability gating that was verified by hand. Mitigating context: this area
  carries 103 passing tests.

The iOS engines audit (`ios/Roam/Models/**`) did complete — see the section
immediately below. Every finding in it was reproduced by compiling the engines
standalone and running them, several with an lldb backtrace.

---

## Open — CRITICAL (iOS engines)

All three of these are **hard crashes**, all proven by execution, and none are
fixed. They share a root cause worth stating once: the engines treat
server-supplied `routeDemands` as trusted, and Swift's trapping operators turn
malformed input into a process kill rather than a degraded result.

### 1. Duplicate demand id traps `Dictionary(uniqueKeysWithValues:)`

`ios/Roam/Models/DriverReadinessEngine.swift:110` — same pattern at
`ios/Roam/Models/RouteChoiceRankingEngine.swift:173`

**Input.** `routeDemands` containing two entries with `"id":"fastRoads"`, then
`DriverReadinessEngine.assess(route:recordedDrives:…)` with any qualifying
history.

**Result.** `Fatal error: Duplicate values for key: 'fastRoads'`.

Today's backend (`backend/src/scoring/demands.ts`) emits 8 fixed kinds, so this
is one server change away. The client performs no dedup at the trust boundary.

### 2. Synthetic insight ids collide with backend demand ids — no duplicate input needed

`ios/Roam/Models/PracticePlanEngine.swift:292`

`assess` appends two synthetic insights with hard-coded ids `"drivingQuality"`
and `"familiarity"` into the *same id namespace* as backend demand ids. A single
demand named `"familiarity"` is enough.

**Input.** One demand `{"id":"familiarity","intensity":0.8,…}` → `assess(...)` →
`PracticePlanEngine.makePlan(assessment:route:)`.

**Result.** `assess` returns **successfully** with ids
`["familiarity", "drivingQuality", "familiarity"]`; `makePlan` then traps with
`Fatal error: Duplicate values for key: 'familiarity'`.

Worse than #1 because the crash is delayed: the bad state is persisted into an
assessment before it detonates.

### 3. Polyline decoder overflows `Int32` on a malformed polyline

`ios/Roam/Models/DriverReadinessSupport.swift:193` (and `:195`)

`RoutePolylineDecoder.decode` accumulates deltas with `+=` into `Int32`.

**Input.** `"}~~~~~@"` repeated 6 times — each component decodes to a
`+1_073_741_823` delta; the third latitude add exceeds `Int32.max`. Reachable
via `matchesPlannedPracticeRoute`, and via `assess(route:)` /
`practiceRouteCoverage`, which both decode `ScoredRoute.polyline`.

**Result.** `Swift runtime failure: arithmetic overflow`.

The decoder already has a `break`-on-bad-component path that this never reaches.
Note it produces nonsense before it crashes: the two-point version returns
latitude `10737.41823`.

---

## Open — HIGH (iOS engines)

### 4. The "Preliminary" gate ignores rejected GPS samples

`ios/Roam/Models/DriveScoringEngine.swift:300-305`, surfacing at
`ios/Roam/Models/DrivingScore.swift:89`

Confidence keys off wall-clock `duration` and never consults
`rejectedLocationSamples`. `DriveExperienceEngine` already computes a real
`traceQuality.usableDuration`; the scoring engine does not use it.

**Input.** `duration: 2700` (45 min), `distanceMeters: 3479`,
`acceptedLocationSamples: 27`, `rejectedLocationSamples: 4000` — roughly 130 s
of usable trace out of 45 minutes.

**Result.** `confidence: high`, `grade: "Excellent"`, summary "This score is
based on sustained GPS and motion data.", and `DriverReadinessEngine.qualifies
== true`. Expected `.low` / "Preliminary" per README:47. **4,000 rejected fixes
had zero effect on the label.**

This directly contradicts the README's central honesty promise. The
`locationInterruptedMidDrive` field added this session covers only the
authorization-withdrawn case — not ordinary GPS starvation (tunnels, urban
canyon, background suspension).

### 5. Unvalidated backend metric traps on `Int` conversion

`ios/Roam/Models/DriverReadinessEngine.swift:684` — same hazard at `:699`

`durationText` does `Int((duration / 60).rounded())` on a value derived from
`expectedDurationMinutes` (`:309-310`) with no finite/range check.
`RouteDemand.init` clamps `intensity` and normalizes `coverageRanges` but never
validates `metrics` at all.

**Input.** `{"id":"sustainedDrive",…,"metrics":{"expectedDurationMinutes":1e300}}`.

**Result.** `Fatal error: Double value cannot be converted to Int because the
result would be greater than Int.max`. `:699` (`recencyText`) has the identical
hazard on a decoded `recordedAt`/`startedAt`.

---

## Open — MEDIUM (iOS engines)

### 6. Synthesized `Decodable` bypasses every hand-written `init` invariant

`RouteDifficultyModels.swift:276-286` and `:305-323`;
`DrivingScore.swift:134-146`; `PracticePlanEngine.swift:94-98`, `:120-130`,
`:155-169`

Five value types do all their clamping and capping in a hand-written `init`, but
keep the *synthesized* `Decodable` conformance — which assigns stored properties
directly and never calls that init. Every invariant is void on the decode path,
which is precisely the untrusted path. Measured (init's value in parentheses):

| Type | Decoded input | Decoded result | `init` would give |
|---|---|---|---|
| `RouteDemand.intensity` | `{"intensity":60}` | `60.0` | `1.0` |
| `RouteDemandCoverageRange` | `{"startFraction":-3,"endFraction":9}` | `(-3.0, 9.0)` | `(0.0, 1.0)` |
| `VerifiedDemandExposure` | `{"demandIntensity":5,"coveredShare":9,"routeShare":-4}` | `5.0 / 9.0 / -4.0` | all clamped `0…1` |
| `PracticePlan` | 7 goals | 7 goals | capped at 3 |
| `PracticeRouteCoverageSummary` | `{overallCoverage:4, longestContinuousCoverage:-1}` | `4.0 / -1.0` | clamped `0…1` |

Two consequences worth calling out:

- `normalized` on `RouteDemandCoverageRange` only swaps when `start > end`, so
  an unclamped range survives, and `DriverReadinessRouteMatcher:203-207` then
  selects *every* sample — a server emitting percent-scale fractions credits a
  5 %-of-route demand as full-route coverage.
- `coveredShare: 9` passes `DriverReadinessProfileBuilder.swift:133`'s
  `>= practiceCoverageThreshold` gate as valid practice evidence.

The "practice plans must cap goals at three" check only exercises the init, so
the test suite cannot see any of this.

---

## Open — CRITICAL

### Snapshot persistence still has a coverage hole on the event path

Partially addressed. The 1 Hz timer now calls `persistInProgressSnapshot()`, so
the two original total-loss scenarios (a motion-only drive persisting nothing;
a stale `lastUpdatedAt` recovering a 50-minute trip as a 2-minute, 0-mile
record) are closed.

Not addressed: `persistInProgressSnapshot` throttles to once per 10 s, so a
termination can still lose up to 10 s of the newest samples. That is the
documented, intended trade-off — recorded here so it is a known bound rather
than a surprise.

---

## Open — HIGH

### `DriveSessionManager` — background suspension is silently absorbed

`ios/Roam/Services/DriveSessionManager.swift:142-147, :593-597`

With *When In Use* authorization, locking the phone suspends the app;
`allowsBackgroundLocationUpdates` stays `false`, so no fixes arrive. The gap is
skipped deliberately (`appendRoutePoint` without distance, to avoid drawing a
synthetic straight line), but nothing increments `rejectedLocationSamples` and
nothing marks the drive.

**Scenario.** User taps "Allow While Using", declines the follow-up Always
prompt, locks the phone, drives 45 minutes. Saved as 45 minutes / 0.2 miles.
The only hint is `DriveScoreConfidence.low`, arrived at incidentally.
`DriveRouteAnalysisEngine` then reports "needs a longer continuous GPS trace"
rather than "the app was suspended".

**Why not fixed.** The mid-drive-revocation fix added
`DriveDataQuality.locationInterruptedMidDrive` for the *authorization* case.
Suspension is a different condition and needs its own signal plus its own
user-facing wording; reusing the revocation flag would misreport the cause.

---

## Open — MEDIUM

### Route planning strands in `.locating` on a coarse GPS fix

`ios/Roam/Models/RoutePlanningLocationCoordinator.swift:106-112`

`useCurrentLocation()` calls the one-shot `requestLocation()`. The delegate
drops any fix with `horizontalAccuracy > 150`, and `didFailWithError` does not
fire when Core Location *succeeds* with a coarse fix.

**Scenario.** User taps "Use current location" in a parking garage; a 400 m
Wi-Fi fix arrives and is rejected. `HomeView` shows "Finding current location"
with a permanent spinner, `planningStage` never reaches `.readyToAnalyze`, and
the Analyze button stays disabled with no explanation.

**Fix shape.** Accept a degraded fix with a visible caveat, or time out into an
actionable message pointing at manual entry.

### Raw response bodies are shown to users as error text

`ios/Roam/Services/APIClient.swift:207-216`

`parseErrorMessage` falls back to `String(data: data, encoding: .utf8)` on any
non-JSON body. That flows to `APIError.httpError.errorDescription` and into the
UI (`HomeView.swift:541`, `ResultsView.swift:424, :465`, `DriveView.swift:388`).

**Scenario.** Backend behind a proxy returns a 502 HTML page. The banner reads
`Server error (502): <html><head><title>502 Bad Gateway</title>...`.

**Fix shape.** Map non-JSON bodies to a generic message; keep the raw text for
logging only.

### Candidate-URL fallback multiplies the timeout

`ios/Roam/Services/APIClient.swift:149-179`

`timeoutInterval = 60` applies per candidate, and the loop treats
`URLError.timedOut` as "try the next host". `candidateBaseURLs` always includes
`http://localhost:3000` (`AppConfiguration:229`), even in a shipping build.

**Scenario.** Weak cellular. Analyze spins a full 60 s against the deployed URL,
then falls through to localhost before erroring — well over a minute, no cancel
affordance, and a real outage reported as a generic connection failure.

Secondary: `deleteDrive()`'s `routeAnalysisTasks[id]?.cancel()` raises
`URLError.cancelled`, which this loop also treats as a reason to fire a *second*
request to the next candidate before unwinding.

### App Group inbox decode failure deletes the shared route

`ios/Roam/Models/SharedRouteImport.swift:575-582`, via
`SharedRouteImportCoordinator.refresh()` → `inbox.peek()`

A decode failure returns `[]`; `peek()` then calls `pruneExpiredEntries` →
`mutate`, which persists that empty list and removes the file.

**Scenario.** User shares a route from Google Maps, then the app updates to a
build where `SharedRouteDraft` gained a field. Opening Roam shows `.idle` — no
card, no error — and the shared route is gone from the App Group container.

This is the same class as the drive-history bug that was fixed; the quarantine
pattern now in `DriveSessionManager.loadRecordedDrives` applies directly.

### Transient redirect failures are treated as permanent

`ios/Roam/Services/SharedRouteImportCoordinator.swift:65-74`

`isPermanentResolutionFailure` treats `.unsupportedRedirect` as permanent, but
the coordinator itself throws that same case at `:51` whenever
`SharedRouteImportParser.parse` cannot read the resolved URL.

**Scenario.** A `maps.app.goo.gl` link lands on a region-dependent consent
interstitial. The parser rejects it → treated as permanent → `inbox.acknowledge`
deletes the link. The advertised retry ("will be tried again when Roam is next
active") never runs, and re-sharing hits the same interstitial.

---

## Open — LOW

### Share extension discards the underlying error

`ios/RoamRouteShareExtension/ShareViewController.swift:297, :314`

`NSItemProvider.loadItem`'s error parameter is ignored, so an attachment that
fails to load is reported with the same copy as a genuinely unsupported link:
"Share a route link from Apple Maps or Google Maps to add it to Roam." The user
retries the same share repeatedly.

### Off-ladder spacing literals

The token sweep converted 66 exact-value matches. These near-misses were
deliberately left because changing them is a design decision, not a mechanical
edit:

- `spacing: 10` — 22 occurrences (between `space8` and `space12`)
- `spacing: 14` — 17 occurrences (between `space12` and `space16`)
- `spacing:` 1, 2, 3, 5, 6, 7, 9, 18, 26, 28 — long tail
- `DriveView.swift:509, :513` — `cornerRadius: 24`; no token exists
  (`cornerRadiusLarge` is 20)

`AppDesign.space4/space16/space24` still have zero uses. The declared 4 pt
ladder and the app's actual 2 pt-granular practice remain unreconciled.

---

## Verified clean

Checked and sound — recorded so this ground is not re-audited.

- **Theming.** Zero hardcoded colors in the view layer; every surface resolves
  through `AppDesign` → `ThemeManager.cachedPalette`.
- **Corner-radius ladder.** Genuinely adopted (53 token uses vs 5 literals
  before the sweep).
- **Backend outbound calls.** All four fetches (`google/routes.ts:147`,
  `google/roads.ts:79`, `enrichment/weather.ts:145`, `enrichment/osm.ts:216`)
  are bounded by an `AbortController` timeout.
- **Backend degradation.** `enrichRoute` uses `Promise.allSettled` with
  per-source `available` flags; `neutralConditions()` carries `sources: []`; and
  every demand in `scoring/demands.ts` gates on both before contributing. A
  weather or OSM outage yields reduced coverage, not a confident wrong answer.
- **Request validation.** Strict Zod schemas on both endpoints, bounded lengths,
  finite/ranged coordinates, a correct ISO-8601 validator, duplicate-candidate
  detection, and failures mapped through `publicFailure()` with no internal
  detail leaked.
- **iOS memory/lifecycle.** Two force unwraps total, both safe. Every `Timer`
  and sensor callback uses `[weak self]`.
- **Re-entrancy.** `startDrive()`/`endDrive()` cannot double-enter;
  `DriveLiveActivityManager`'s `requestedDriveID` handshake correctly resolves a
  fast start→end race; CarPlay connect/disconnect does not disturb an active
  recording.
- **APIClient.** Does check HTTP status before decoding (`:194`) and does set a
  timeout (`:178`). The defects above are about *which* timeout and *what* is
  shown, not their absence.
- `ChartContent.cornerRadius` is **not** deprecated — only `View.cornerRadius`
  is. An earlier draft of this file claimed otherwise.

---

## Open — structural clutter (copy was tightened; layout was not)

A copy pass unified terminology to the README's vocabulary and removed redundant
text. These four are density problems in the *layout*, which shorter words
cannot fix — each needs a product/IA decision:

1. **`ResultsView` is one very long flat scroll** — up to eleven stacked
   `premiumCard()` sections. The readiness card alone nests a summary, a history
   block, an expandable insight list, a practice plan, a CTA, and a disclaimer.
   Wants grouping or progressive disclosure.
2. **Progress and Profile now visibly duplicate content.** After-dark miles,
   45+ mph miles, longest continuous trace, the eight-week chart, and the /100
   score appear on both tabs. Unifying the labels was the right copy fix, but it
   exposes that neither tab clearly owns these metrics.
3. **`ReadinessHistorySummary`** packs a `·`-joined line plus three label/value
   pairs into an already-nested card — the "8 PM–6 AM" definition had to be
   dropped for space. If that window matters there, the row needs a detail line
   like the Progress coverage rows have.
4. **`DriverProgressView.overallScoreCard`** carries seven pieces of information
   about a single number (icon, title, evidence tier, 40 pt score, progress bar,
   `ViewThatFits` signal row, detail paragraph).

---

## Test runner

`ios/tests/*.swift` are standalone `swiftc` checks; `README.md` documents six of
the sixteen. A runner covering all of them lives in the session scratchpad at
`verify.sh`. Three checks fail under it only because its source set omits
`ios/Roam/Features/Home/RoutePlanningFormModel.swift` (`RoutePlanningStage`,
`RoutePlanningFormReducer`) and SwiftUI context for `LayoutResponsiveness` —
a runner gap, not a product defect. Promoting a corrected runner into the repo
and documenting all sixteen in the README would be a worthwhile follow-up.
