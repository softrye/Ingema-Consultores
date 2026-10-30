# Calicatas approved entry design implementation plan

> **For agentic workers:** Use superpowers:executing-plans, sequentially. The user has approved the supplied screenshots and explicitly requested implementation now, without compilation or another approval round.

**Goal:** Replace Android's old entry mosaics/modal editors with the approved direct-field mobile design and Web field contracts, preserving Android Photos and Summary.

**Architecture:** Keep CalicataFormPage as the single document controller and its existing ListModel, live collaboration, commit, persistence, map, and export paths. New focused QML entry controls project these same values; a pure JS contract handles presentation validation and coordinate drafts. Remove superseded entry bodies rather than hiding another editor behind a feature flag.

**Tech stack:** Qt 6.9.3, QML/JS, existing C++ CalicataDocument and InGeCoreFlow, Android arm64-v8a.

**Spec:** User images codex-clipboard-8196ce62-d5bc-4b43-8430-1acf100d3b80.png and codex-clipboard-4f4a80cf-31d6-4444-8cf5-54ae1fad8d53.png, plus reviewed Web field behavior. Photos and Summary are explicitly excluded from redesign. Existing repository contract remains authoritative for persisted/server enum values; screenshot labels are presentation.

## Global constraints

- No CMake, build, qsb, APK installation, restart or logout; user compiles.
- Qt 6.9.3 / Android arm64-v8a; one InGeCoreFlow; one active form.
- Preserve AuthSession, Login, Home, account isolation, local data, Photos and Summary.
- No server schema/policy changes, secret logging, fake save states, or masking fallbacks.
- Preserve unrelated working-tree changes and commit only this task's changes per phase.

## Review focus

- Partial numeric/coordinate drafts survive typing, validation, tab changes and incoming state without cursor jumps.
- Repeated list edits preserve row identities; changing selection commits the correct stratum.
- Decimal/DMS representations convert to canonical UTM without persisting malformed or partial pairs.
- Lab percentage ordering, nonplastic values and composite classifications preserve the Web/domain rules.
- Old saved stage indexes still open Photos=4 and Summary=5; Notes is a new stage with explicit navigation ordering.

## Phase 1: Entry contracts and focused controls

- [ ] Write failing host tests for header validation, coordinates/DMS, navigation ordering and unchanged protected sections.
- [ ] Add CalicataEntryLogic.js plus focused field/choice/form QML controls; use existing domain functions for canonical rules.
- [ ] Run JS host tests and syntax checks without building; commit the foundation.

## Phase 2: Replace active entry UI

- [ ] Connect new controls to existing document/strata and commit/autosave/live methods.
- [ ] Replace General, Location, Field, Laboratory and Notes bodies; remove obsolete entry popups and dead entry-only controls.
- [ ] Preserve Photos and CalicataReview bodies byte-for-byte; preserve stage IDs and review links.
- [ ] Align CMake/resource declarations with new local QML/JS files; do not run CMake.
- [ ] Run contract/regression tests, inspect references to removed IDs, and commit integration.

## Phase 3: Host UI validation and handoff

- [ ] Exercise real QML controls in an existing Qt host runner: typing/commit/error preservation, selection, fields, stage ordering and read-only values.
- [ ] Check QML parsing, relevant existing regressions, protected-section hashes and diff hygiene.
- [ ] Record commands, limitations and required device checks; commit documentation/tests.
- [ ] Report source completion separately from pending user build/device verification.

## Handoff: user requested stopping before implementation

Only this plan was added. No application source was edited for this redesign;
no tests, build, installation or device actions were performed for it.
The user explicitly wants implementation in the next session and brief output.

Findings to resume without repeating discovery:

- `CalicataFormPage.qml` is ~13.5k lines. Existing entry is a General mosaic
  (around 10904), Location (11029), Profile (11854), Lab (13017), plus modal
  `stratumSheet` (9764). Observations is around 13419. Line numbers may drift.
- Protected Photos body starts `MobileStageBody { id: mobilePhotosSection`
  (sectionNumber 7, around 11513); verify actual id before extracting. Protected
  Summary is the `CalicataReview` instance around 13345. Preserve both bodies.
- Existing stage IDs: General=0, Location=1, Profile=2, Lab=3, Photos=4,
  Summary=5. Add Notes=6 and explicit visual/navigation order rather than
  shifting persisted IDs or hard-coded Photos/Summary conditions.
- `sectionNavigation`, `sectionPosition`, `sectionVisible`, swipe target and
  goNext/goPrevious currently assume numeric adjacency; update together.
- Expose header/controller adapters to new focused local QML components;
  preserve `cortesModel` and `_pendingCommitFields` / `commitPendingField()`.
- Hidden inputs `txtCodigo`, `txtPk`, `txtSupervisor`, `txtMaquina`, `txtUTMX`,
  `txtUTMY`, `txtUTMZ`, `txtZona`, `txtWaterTableDepth`, and buttons
  `btnFechaInicio`/`btnFechaFin` currently feed exportState/importState.
- Existing canonical helpers: `_setCanonicalCalicataCode`, `_setProgresiva`,
  `commitProfileDepth`, `commitProfileGroundwater`, `commitBoundary`,
  `commitWebLabPercent`, `commitLabLimit`, `setWebLabMeta`,
  `setLabClassification`, `setLabSampleType`, `_manualCoordinatesChanged`,
  `_changeDatum`, `_openProjectPicker`, `_openDatePicker`.
- `CalicataRules.js` already has Web catalogs, percentage bounds, integer LL/LP,
  depth increments and UTM/datum conversions. Screenshot numeric examples and
  labels must not override actual server contracts (e.g. fractional LL/LP).
- General popups to retire: `generalIdentityPopup`, `generalDatesPopup`,
  `generalExcavationPopup`. Preserve `identityPopup` until checking Photos:
  it manages Android logos, which the user explicitly excluded from redesign.
- Removing old profile/lab UI requires updating remaining references to
  `prfEditorCard`, `stratumSheet`, lab detail state/scrim and Dock actions;
  do not introduce dummy popup objects or leave dead ID references.
- Reuse the existing Location preview (`CalicataPointPicker.qml`) and map
  action. No second map provider, Flickable/IME strategy or animation engine.
- Register new files consistently in CMake near CalicataFormPage (~623) and
  resources.qrc (~93); no CMake/build execution is authorized.
- Full working-tree baseline: `artifacts/calicata-entry-baseline.json`.
  It captures five relevant sources before this task. Repo has extensive
  unrelated changes; do not stage them wholesale.
- Last implementation commit before this plan: `9222e0e` (first-open presence
  and media). The preceding HTML preview is outside the repository and is not
  the approved final design; follow the user's two latest screenshots.
