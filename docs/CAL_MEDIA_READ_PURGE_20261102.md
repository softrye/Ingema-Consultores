# CAL-MEDIA-READ: purged Calicatas retained as historical rows

Project: InGePlus-Dev (`aalmeaqhhlhzwwzsbbxz`) only. No other Supabase project
was queried or modified. No compilation, installation, logout or local-data deletion.

## Proven cause: hypothesis (b)

Read-only queries: `tests/calicatas/sql/media_purge_evidence_20261102.sql`.

| Project prefix | UPLOADED | Missing original objects | In purge domains AND object list | Affected Calicatas |
| --- | ---: | ---: | ---: | ---: |
| f4547c5d | 29 | 29 | 29 | 2 |
| f066cb63 | 9 | 9 | 9 | 3 |
| 7fb77795 | 19 | 0 | 0 | 0 |

All 38 missing original paths belong to CALICATA entries in
`preview.domains` and occur in `preview.objects` of purge
`5ced58f5-ef83-4ce3-971f-a5a74a472367`. Missing originals outside those
domains: **zero**. All five affected Calicata rows and their media rows survive.
The purge started at 2026-10-12 14:29:52.517135 UTC and completed at
14:30:00.590598 UTC. `files_document_purge_entities_v06` contains document
node/space IDs, not the Calicata domain IDs; joining that table directly to
calicata_id incorrectly suggests the media was outside the purge.

`private.can_read_calicata_media_v01` already excludes frozen domains, including
all 38 affected media. An authenticated administrator already saw only the 19
remaining UPLOADED media before this fix. Recovery/archive policies include
restrictive policies; they are not an authorization OR bypass. Historical
Calicata rows and local mirrors lacked an explicit PURGED read contract.
Storage's not_found response alone cannot distinguish physical absence from
permission denial. The uncommitted automatic re-upload on that response could
resurrect a purged document and was removed.

## Applied server phase

Migration: `20261102144156_calicata_purged_media_read_state_v01.sql` (remote
version verified against migration history). No business-row updates/deletes.

- Private completed-domain predicate uses completed purge metadata and the
  existing frozen-domain helper. A live binding admitted by that helper is
  not silently classified PURGED from historical metadata alone.
- Authorized read RPC `get_my_calicata_media_read_state_v01(project, calicata)`
  reports ACTIVE / PURGED / FROZEN and READY / MISSING object existence.
  With null Calicata, it returns scoped lifecycle IDs for active-list filtering.
- Restrictive read guards exclude completed purges from Calicatas and media.
  Existing history and local copies remain intact; no purge algorithm changed.
- Explicit active-profile/project/document authorization, empty search_path,
  no anonymous execution, no credentials or signed URLs in the result.
- Manual rollback: `docs/sql_proposals/ROLLBACK_calicata_purged_media_read_state_v01.sql`.
  It removes only the newly introduced policies/functions; not applied.

Real authenticated SQL verification after migration: 11 surviving Calicatas
reported PURGED in the two affected projects, eight ACTIVE in 7fb77795,
zero purged Calicatas visible through the table, 19 UPLOADED media still visible.
The 16 non-discarded media returned by the active-document RPC have READY
originals: 12 also have READY derivatives, four have no derivative. All 38
historical missing rows remain untouched. Anonymous EXECUTE=false;
authenticated EXECUTE=true. Security/performance advisor baseline comparison:
**no new findings**.

## Android phase

- Account-scoped, persisted last-confirmed PURGED IDs filter remote and local
  Home tiles without deleting drafts. Fresh authorized ACTIVE responses clear
  those cached IDs. Switching accounts resets/reloads the proper owner's cache.
- Photos/logos preflight the lifecycle before metadata adoption. The common
  calicata-media signer checks again immediately before requesting a URL.
- An original reported MISSING is not signed. PURGED never reaches signing.
- The outbox preflights before publishing; PURGED entries/files are retained
  as terminal local records and excluded from pending/error indicators.
- OBJECT_NOT_FOUND never triggers automatic enqueue/new_original. MISSING and
  PURGED have explicit neutral read states; real auth/network/image errors remain.
- A missing/failed annotated derivative no longer silently adopts the original
  as though the requested derivative had downloaded successfully.

## Verification and limits

Host JS: `node --test tests/calicatas/media_purge_read.cjs tests/calicatas/first_open_presence.cjs`.
Existing regressions: `node tests/calicatas/health_glass_logos.cjs` and
`node tests/calicatas/photos_static.cjs`. QML parsing: qmlformat, stdout
redirected to private artifacts without editing sources. Real host QML tests
exercise purge filtering and draft retention; final result recorded in artifacts.

Decisions: implement (b), do not change purge object-selection logic; retain
historical/local records; eliminate automatic repair uploads; preserve genuine
errors; coalesce concurrent preflights and scope all state to account context.

[Historical Storage deletion/access logs were not available in this verification;
the object-list/domain correlation and completed purge demonstrate scope, but
do not independently reconstruct the physical delete HTTP calls.]

[Android compilation, signed-URL HTTP download on the phone, visual regression,
and Login/AuthSession/multiaccount/Profile/Home device regression remain pending
the user's build. Existing bytes and authorized RPC states were checked by SQL;
this does not substitute for a real device download.]
