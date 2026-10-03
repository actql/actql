# Public Graph surface cleanup

Bounded follow-up for [#231](https://github.com/actql/actql/issues/231), after
[#164](https://github.com/actql/actql/pull/164) integrated at
`f11408cc8afdce81829d5d63de5bca3ae043d065`. Inspected current main:
`4303f0681c7e7ae3544563fa9dd6d7e5c0eebd41` (also includes #234 and #243).
The earlier local preparation used `88fbcc95306abb4fc41f0d488bcc6d38ec19506d`;
all seven proposed paths were unchanged when rechecked against current main.

## Removals and replacements

| Surface | Current callers and disposition | Replacement and validation |
| --- | --- | --- |
| `scripts/accept-sga-public-source.mjs` | Orphan application: attempts positive execution of retired tuple Programs and old Reach/shortest consumers. The current packed driver no longer copies or invokes it. Its only executable self-reference is its usage text. | Existing `scripts/test-node-client-package.mjs` checks current keyed MATCH/TRAIL through installed Local/HTTPS Clients. `scripts/test-packed-property-graph.mjs` uses the independent keyed Program and the existing snapshot/refusal oracle. Remove the obsolete runner, not its historical fixtures. |
| `scripts/reproduce-sga-baseline.mjs` | Standalone diagnostic for retired reach/subgraph, equality and diff/apply Programs. No workflow, package command or other current executable script calls it; only its usage text names itself. | Existing `scripts/property-graph-public-host.test.mjs` derives unsupported-consumer cases from the authoritative family inventory and verifies refusal before durable request registration or physical work. Old consumers are not rewritten as successful current examples. |
| `scripts/diagnose-sga-provider-handoff.mjs` | Standalone diagnostic using the retired tuple inputs and a numeric-only checker profile. No current executable caller. Historical reviews describe its earlier output. | Existing `scripts/property-graph-surface-checker.test.mjs` exercises the current admitted profile and common Plan/Host owners. Keep the current profile's positive ownership, resource, failure and cleanup checks. |
| Root README `graph` / node-emitting blast-radius excerpt | Public prose still presented the removed constructor and an unconnected traversal form as an example. | Replace only the Graph block with the literal constructor/MATCH steps in `scripts/fixtures/property-graph-parallel.program.json`, link the complete public JSON Program and state its independently expected two edge rows. The focused documentation test compares the parsed excerpt to that hand-authored fixture and checks both links. |
| SGA fixture README's current-execution descriptions | Its preamble and one paragraph still called tuple machine Programs current execution fixtures, despite the later retirement notice. | Correct those current applicability statements only. Preserve the recorded earlier SHAs, algorithm expectations, historical rows and all source/Program/Result fixture bytes. |

Caller inspection covered 459 tracked paths: every file under `scripts/` and
`.github/`, all package manifests and root commands at the inspected source.
Package export maps and current Graph/Frontend public interfaces were also
inspected. There are no repository `SKILL.md` files or nested `AGENTS.md` files in
that tree. Static imports, dynamic imports, child-process commands and copy
lists in the current packed drivers do not name the removed scripts. A bounded
repository code search identified references in the September 29 historical
review records; their current file contents were checked and left unchanged.
This is not a claim about arbitrary external consumers of these internal
diagnostic scripts. Git retains the earlier executable versions.

## Preserved boundaries

- Package exports already use the current Client/Host paths. No Graph package
  alias, conversion reader or new public entry is introduced or removed.
- `scripts/test-native-sga-public-source.mjs` already uses the keyed JSON
  fixture; it stays intact. Its source-text expansion belongs to #237.
- `scripts/fixtures/packed-sga-cancellation.mjs` already exercises the current
  keyed Program and remains registered. Its legacy filename is not obsolete
  behavior.
- `scripts/sga-surface-checker.test.mjs` already refuses the retired tuple
  constructor with the current profile installed. Do not duplicate or delete
  that regression. The existing public Host inventory supplies the separate
  unsupported-consumer refusal checks.
- Historical internal syntax comparisons and their Reach fixture helper are
  retained: they do not supply a public compatibility path. Historical laws,
  CIDs, proof sources, provenance and the authoritative capability/resource
  inventory are unchanged.
- #233/#235/#237/#240 own current source-language connection and its coverage;
  #232 owns selected traversal routing. This cleanup does not adopt their
  unmerged code, edit shared runtime/identity/snapshot/resource owners, or
  claim all-SGA or source-language completion. All eleven current open PR file
  lists, including newer #242 and #244, were checked; this patch does not edit
  their files.

## Focused verification

The patch was reapplied to freshly verified current-main inputs. On the final
edited files:

- `node scripts/local-checks.mjs test node --timeout-seconds 60 -- scripts/document-validation.test.mjs`: **12/12 passed**, no skips. The existing `test:docs` registration includes this file; no additional suite or CI job is introduced.
- A negative control changed only the README's `property_graph` key back to
  `graph`. The new test failed as intended (**0 passed, 1 failed**); restoring
  the excerpt returned the complete focused file to **12/12**.
- `node --check scripts/document-validation.test.mjs` and `git diff --check`
  passed. All links in the three changed Markdown files passed the existing
  document-link validator, including the new contract anchor.
- The owned-contract-version guard passed against the materialized files;
  its three focused regression tests also passed. No inventory exception or
  version change was added.
- The 459-path caller scan passed after the three intended removals, with no
  other missing paths or remaining executable references to those runners.

The initial full-file documentation attempt had two JSON-input failures:
GitHub's contents endpoint supplied empty bodies for the two schemas larger
than 1 MiB. The schema blobs were fetched through the blob endpoint and their
Git SHA-1 values verified before the successful final run. No schema was
changed. Cached root JavaScript dependencies were reused in this selected-file
source materialization; it is not a full repository checkout or a fresh install.
Every materialized baseline file was checked against its current-main Git blob
SHA. The patch changes only the seven listed public-surface/test/report paths;
no foundation declaration, frozen contract, provenance or runtime bytes change.

The README check validates documentation correspondence, not execution.
Existing independently authored expectations remain in the unchanged public
Host and packed Client suites; no new expected rows, CIDs or schemas were taken
from product output. Whole Core/spec suites, native builds, fresh packing and
hosted CI were not run locally. Publication uses the ordinary pull-request CI;
the submitted commit and its observed CI result are recorded on the PR rather
than inferred from these focused checks. No manual rerun or deployment is part
of this cleanup.
