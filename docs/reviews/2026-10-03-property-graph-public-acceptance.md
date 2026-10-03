# Unified Property Graph public source acceptance

Status: development acceptance and pushed-source Client packed/spec CI passed;
dependency/PR review and the remaining required CI jobs are pending.

## Fixed source and dependency

- Acceptance source: `a6675aa5945389e66aa15978c9ed0ae66cbe69a1` (clean checkout).
- Source integration: `d9aba0da0c34f0335d0a2c60c8d42333badbfcbb`.
- B parent: `b19ed2cfb0bdce93832d47a8c3a7a8da95266c14`.
- C parent: `51376bca11d57b775aa22d42453176f8ad1f681b`, #164.

The old provisional #174 implementation is preserved as historical work, not
used as an execution fallback. This independent integration uses the unified
constructor/checker/Carrier/MATCH/TRAIL/snapshot owner in ActQL. It adds no
Graph executor, storage codec, authorization owner or Run-start owner.

## Reproduction and evidence

Use the pinned repository toolchain and normal dependencies:

```sh
node scripts/test-packed-public-query.mjs --property-graph-source-only
```

The driver normally prepacked five public packages at the fixed source, installed
them outside the checkout with runtime install scripts disabled, and exercised
Local and HTTPS with no MoonBit toolchain on the consumer PATH. Source and
expected rows/columns are independently authored in
`scripts/fixtures/property-graph-source-input.mjs`. It checks public
`Result.describe()`, rows, stream completion, attach, reread and request reuse.

For **each** of Embedded Local and HTTPS:

- 18 source successes (3 Relation DATA controls and 15 keyed Graph cases).
- 3 duplicate-key execution failures: node, edge, and duplicate edge whose
  missing endpoint must not hide the invalid key. Failed Results cannot be read
  or described; request reuse does not start a new Run or computation.
- 12 typed input refusals, including unadapted SGA consumers and retired Graph
  inputs. Actual Run admission/provider I/O counters stay unchanged and request
  lookup is `not_found`.

The keyed cases cover same-definition and definition-scoped parallel edges,
WALK=4/TRAIL=2/ACYCLIC=0, composite node/edge keys, Graph-owned static labels,
property/label separation, case-insensitive label membership, nullable keys,
missing/NULL endpoints, typed empty Results and explicit projection followed by
star. Internal identity columns are absent from the authored public schema.
The ordinary full packed application now includes these cases too.

The same installation ran `property-graph-public-host.test.mjs`: **2/2** Local
and HTTPS tests passed. These are independently authored **JSON Program controls**
for constructor/MATCH/TRAIL plus exact physical save/revoke/read/reload bytes,
identity preservation and temporary-body reclamation. They additionally reject
17 inventory-classified consumers, with/without external input, before Run or
physical work. Their exact snapshot CID assertion is not relabeled as a separate
source-constructor snapshot CID assertion.

README Local/HTTPS acceptance and the negative missing-generated-asset check
also passed. The evidence invocation is `public-query-evidence-Ri2ldR`;
its complete summary records this clean SHA, command logs and package digests.
Successful temporary installations were reclaimed after evidence was saved.

## Package correspondence

| Package | SHA-256 |
|---|---|
| actql-client-wire-0.0.0-development.tgz | `5da98d3edb615f960f0511be9d6e61431cd34d02304a8bd6b6e576f7775f91a0` |
| actql-sdk-0.0.0-development.tgz | `2fc910067348e421346945ced1e728e107bbe6fa455ee00f9d71da46e8123c5b` |
| actql-run-host-core-0.0.0-development.tgz | `89b73b4d874d2972586eccc4ebde2b6af810c3c1b548dfeef11dc4ccc8a5bf30` |
| actql-local-node-0.0.0-development.tgz | `61a8ae944d7f2e2c9d72447f166d39182fcb5ea762c62c768f6cb9916919194a` |
| actql-node-0.0.0-development.tgz | `89a340b9d0a80c4ade483e471c06a5503f81c347ced3a17f3c4e4d4a21b1eb64` |

## Other validation and remaining work

- Source boundary: 5/5 JS; keyed lowering/property predicates: 4/4 JS.
- Independent Run preimages: 2/2 Node; common Run material issuer: 1/1 JS.
- Three-target public API consistency, `check:contracts`, regenerated fixture
  freshness and committed foundation composition passed.
- The complete `check:spec` attempt is incomplete: it passed Relation execution
  1,094/1,094, then was interrupted during the slow resource-audit test under
  high load. No guard was bypassed. Required final CI remains pending.
- Native CLI execution was not rerun locally. Pushed-source Client packed CI
  later passed its JSON Program Graph control; this is not authored Graph text
  CLI acceptance.
- Unadapted SGA consumers remain unsupported; source-INFER remains a separate
  common-owner dependency. Neither full SGA nor the full Frontend migration is
  declared complete. No main merge or package publication was performed.

See [connection boundaries](2026-10-03-property-graph-unified-source.md) and
[migration checkpoint](2026-10-03-frontend-migration-checkpoint.md).

## Authored source snapshot follow-through

`scripts/property-graph-source-snapshot.test.mjs` submits authored DATA /
PROPERTY GRAPH text through the installed Client, ordinary checker and Host.
Two distinct self-loop edge keys must survive the common physical snapshot
save/read/reload route and yield exactly two ordered two-hop TRAIL choices.
Named Result rows and column contracts are independently specified. The awaited
Host observation confirms one saved Graph, verified read bytes, original-carrier
release, successful restoration and temporary snapshot-body reclamation.
Attach, reread and identical request resubmission cause no new physical events.
No frontend storage codec or Graph executor is introduced.

The narrow packed editing run `public-query-evidence-SAHW9F` passed the existing
18/3/12 source cases per transport and **4/4 snapshot tests**: two common JSON
controls plus two authored-source Local/HTTPS cases. It records committed
baseline `326074ca2a32b00f6d79d0357ff34da9a5245409` with the new test/harness
edits present (`dirty: true`), so
this is editing evidence, not clean final-SHA evidence. It uses the same five
package digests as the clean acceptance above. Final pushed-SHA CI must verify
the committed tests. This source observation does not independently assert the
exact canonical snapshot CID; the exact-byte/CID oracle remains the JSON control.

The initial direct checkout invocation stopped before Host startup because a
borrowed dependency resolved an older Client wire export without `validCheckOutcome`.
The fresh installed packages passed; the borrowed dependency was not modified.


## Full-corpus request registration correction

The first pushed-source CI run
[37092716948](https://github.com/actql/actql/actions/runs/37092716948) found
that the default full selection registered the three shared Relation DATA
controls twice. Local cases themselves passed; their identical request IDs
correctly reused existing Runs, so the actual accepted count was 120 while
the fixture incorrectly expected 123. Narrow Graph selection was unaffected.

The correction keeps the first equivalent fixture for each request name,
asserts exact source/options/expectations equality for shared names, and
rejects conflicting duplicates. It changes no result expectation, Run owner
or request identity. The combined Relation/Graph corpus has 18 distinct
requests; the two composition regressions pass and are imported by the
existing packed-query evidence CI entry. That registered test entry passes
22/22 locally. Full-corpus verification on the corrected pushed SHA passed,
as detailed below.

## Pushed-source CI evidence

At `b3ad31f342a097dd2bbed5050e267b1b15b4e9f7`,
[CI run 37093230414](https://github.com/actql/actql/actions/runs/37093230414)
completed the Client packed and spec jobs successfully. The full run is not yet
recorded as successful while other required jobs remain in progress.

The `packed-public-query-b3ad31f342a097dd2bbed5050e267b1b15b4e9f7-37093230414-1`
artifact records invocation `public-query-evidence-wJZruU`, a clean source,
14 successful commands, complete output and successful temporary-install cleanup.
Its five package digests exactly match the local acceptance table above.
The ordinary full corpus includes all selected Graph source cases on Local/HTTPS
alongside existing SQL/Pipe, scope, parameter, Result and retained-recovery cases.
It also passed the common snapshot controls and the native Client's independent
parallel-edge JSON Program through Named Results. That native control is machine
input evidence, not source-text CLI execution or migration of remaining SGA calls.

The complete spec job success closes the pushed source's aggregate spec validation;
the earlier interrupted local attempt remains recorded as incomplete. Later
documentation-only changes do not alter these executable sources or artifact bytes.
