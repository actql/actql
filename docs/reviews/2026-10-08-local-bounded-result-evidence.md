# Resumed retained Result dependency validation

## Completion unit and integration

This closes the Result dependency and Artifact provenance scans inside the
existing Effect-free publication commit preparation. It does not close all
publication metadata traversal or the whole retained Local goal.

PR #934 is merged. This branch normally merged main
`2d38f1ccf8134ebb96446ef9cb1e53767a704200`, without conflicts, and targets
main without an unmerged prerequisite. The implementation/test source is
`54fc14772a0cdbda77605d472ed32bd70748d3d7`. Subsequent record-only changes
retain the source provenance of each check below.

## Existing owner connection

`ResultEvidencePreparation` borrows admitted contracts and resolves each
Artifact's exact Definition, Ordering, Derivation and Retention references.
Retention duplicates, occurrence-use flags and exact-match searches advance
one entry per control step. Flags are initialized incrementally and reserved
before insertion. No whole inventory filter, copy or sort is needed.

`ResultArtifactCheck` preserves the previous scalar guard order, then reads
the immutable provenance array one entry at a time. Ordering-profile checks
use array count/index access instead of copying arrays that must contain
zero or one entry. Existing typed dependency, duplicate and Artifact causes
are unchanged. A shared retention is permitted only when all supplied
retentions are used; derivation and ordering occurrences remain one-to-one.

`PublicationCommitPreparation` polls this child before durable bindings and
computation checks, supplies its remaining workspace, records the peak, and
retires private state on success, failure or cancellation. The caller's
contracts and Store custody are not released by validation cleanup.

Explicit blocking validation functions drain these same private checks.
They are not a fallback chosen by the connected retained Host. There is no
new admission rule, wire shape, CID preimage, ledger or commit authority.

The existing commit-first reconciliation rule is preserved: cancellation
does not discard an already committed authoritative outcome. The private
continuation cancellation tests below are not evidence of aborting a durable
commit. Fresh-publication cancellation remains at its existing precommit
context/row validation boundary.

## Independent acceptance

Common fixtures cover two Results sharing one retention, duplicates,
missing dependencies, empty inventories and a long
provenance list with its required derivation last.

The workspace expectations are authored from reserved private state:
sixteen owner slots, two occurrence flags per Artifact, one flag per supplied
retention, and eight slots for the provenance child. Two Artifacts and one
retention require 29 slots; 28 refuses with `CommitEncoding` before starting
the child. Empty input requires the sixteen-slot frame. These are logical
workspace reservations, not a measured byte-allocation or latency guarantee.

For A Artifacts, R retentions and P provenance entries per Artifact, the
successful fixture's control transitions are independently counted as:

```text
5 + R + R*(R-1)/2 + 2*A + A*(3*A + R + 8 + P)
```

Two Artifacts with R=1 and P=1 require 42 transitions at quantum 1, 7 and 64.
The 32-Artifact case requires 3,462 transitions and 89 workspace slots at
quantum one; each reference scan advances by one index, and initialization
starts with empty use inventories. These are control-step totals, not a new
definition of Compute's contractual logical work.

Cancellation at retention scanning, flag initialization, reference lookup
and partial provenance scanning clears private flags and borrowed roots,
returns live reservations to zero, and leaves the supplied contracts valid.
The required derivation at provenance position 129 cannot be found in one
poll; removing it preserves `ArtifactMissingDerivation`.

The normal retained Host success case now requires multiple polls while
still in `result-evidence`; a synchronous whole-set check would fail this
assertion. It continues to read the producer and both consumer Named Results
from real Stores, using independently fixed Unicode/NULL rows and exact
order. Existing context/row cancellation prevents contract writes, attempt
creation and publication, followed by zero retained resources and no extra
Compute dispatch. Portable control cases retain committed replay under an
already-aborted request and concurrent cleanup reconciliation.

## Executed verification

Commands use the repository-pinned Node/MoonBit environment.

```sh
node scripts/local-checks.mjs test moon --timeout-seconds 180 -- \
  --target js --jobs 1 src/run_publication
node scripts/local-checks.mjs build moon --timeout-seconds 180 -- \
  --release --target js --jobs 1 src/connectors_builtin_node \
  src/connectors/duckdb/conformance
node scripts/local-checks.mjs test node --timeout-seconds 180 -- \
  --test-name-pattern 'portable control validates Receipt and Captured Run references|retained publication validation yields before commit|retained Captured Run issuance yields through final evidence checking' \
  adapters/host-common/publication-contract-control.test.mjs \
  adapters/connectors/duckdb/node/test/retained-values-chain.test.mjs
```

- Common JS: 256/256 at integrated source
  `532ac3168d2de45a4d90a10b44148d55e930da2b`; bounded receipt
  `run-1iyv2v`, focused receipt `focused-test-Whpxva`.
- Release runtimes: 39 incremental tasks, receipt `run-QV0sjh`.
  Compiled inputs are identical to the source above. The later source commit
  only adds the Host observation assertion; `git diff --exit-code` over
  `src` and `scripts` confirms identical inputs at the verified source.
- Selected Node: 8/8 at clean source
  `54fc14772a0cdbda77605d472ed32bd70748d3d7`; bounded receipt
  `run-8yJeHh`, focused receipt `focused-test-1xWnAl`. Seven top-level
  cases include six actual retained Host cases; one nested cleanup case
  accounts for the eighth test. These consume checkout release runtimes,
  not pristine packed tarballs.
- Selected `moon info`, read-only Node/RelA generation, Node Host/Workers
  fixture freshness, Node syntax and patch whitespace checks passed.
  No tracked API regeneration change was required.
- Feature commit messages follow Conventional Commits, with every line at
  most 72 characters. Implementation, integration, Host acceptance and
  record changes are separate reviewable commits.

Receipts remain under `_build/local-checks/attempts` and
`_build/focused-evidence`. Earlier unsuccessful checks remain distinct:
`run-aSeqyq` found syntax/fixture-construction errors; `run-0p9hRm` passed
253/254 with the negative fixture using the wrong self-identity field.
Neither is reported as passing acceptance. Generator commands without the
pinned toolchain environment also refused before the successful checks.

## Formatting follow-up

The follow-up inventory work found that the earlier multi-path `moonfmt`
invocation did not format every supplied file. The affected sources are now
formatted with one invocation per file, and stdin/output comparisons check
the resulting bytes. The correction does not change validation logic or
contract literals. Previous execution receipts retain their original source
provenance; a formatting check is not a fresh execution or hosted CI result.

## Remaining boundaries

Durable binding inventory checks, request/index inventories, long Result
name and namespace comparisons, computation metadata preludes, field-name
normalization and other scalar schema checks still contain synchronous
work. Effectful commit validation and explicit blocking Native/direct
consumers remain separate connections. Contiguous allocation latency is
not bounded by the transition evidence above.

Full Core, Wasm/native execution, pristine packed/HTTPS acceptance, proof
campaigns and performance measurements were not run. No hosted CI success
is claimed. Draft preparation and required Ready/integration coverage must
remain distinct. The next implementation unit is durable binding and commit
reference inventory traversal, using the same commit owner.
