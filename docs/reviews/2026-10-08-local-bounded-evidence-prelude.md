# Resumed retained evidence preludes

## Completion unit and baseline

This unit resumes publication root inventories and embedded computation
evidence checks through the existing retained Effect-free Host owners.
It does not complete the whole retained Local objective.

The final tested Host source is
`036cf1464d80ba6dcd7cc4de26b3b2affa716590`.
Common JS and release runtimes were verified at
`1af92adb7ef8f48c5b834f16bb43ce7cd490e8e0`. The subsequent commit changes
only the Host fixture synchronization; `git diff --exit-code` confirms its
MoonBit sources, generators and build inputs are identical.
PR #941 merged during development. The branch normally adopted main
`3ecde2bc0968212bfb98a0387586ceb2188be90c` without conflicts.
The incoming changes outside #941 were proof evidence, not overlapping
production implementation. The new PR targets main with no unmerged parent.

## Common owner connection

`EvidenceStreamPreparation` polls the existing canonical emitter.
Each transition drains its bounded writer; exact wire and pair comparisons
retain offsets and process at most 64 UTF-16 units per comparison step.
Hashes are used only for declared identity checks, not as a replacement for
exact value equality. Raw Unicode, decomposed strings, CR/LF, nested values
and explicit NULL retain their existing canonical meaning.

The writer reserves a 512-byte batch and its potentially coexisting drained
fragment before allocation. Emitter frames and private child frames are
accounted separately. A mismatch does not skip the remaining emission:
writer byte/node/depth refusals still retain their required precedence.

`PublicationRootPreparation` borrows immutable contracts and manifest
results. Definition/Artifact kinds, inventory names, cardinalities, exact
Artifact lookup, invocation binding and embedded Artifact wire equality
advance with cursors. Long names reuse the existing UTF-16 fragment
comparator. Missing, duplicate and foreign inventories keep their typed
refusal order. The blocking root API drains this same owner, not a second
algorithm.

`ComputationPreludePreparation` connects this root child, prepared and
authorization identities, observation identity, exact embedded manifest,
artifact inventory equality, Source identities and external observations,
and exact captured Receipt wire. Model references are reserved before
append and transferred to the existing continuation only on successful
completion. The old synchronous prelude is removed.

Captured Run issuance also polls the root owner before context preparation.
Authoring kind admission still precedes the root check. All later snapshot
and dependency admission keeps its original order. Private cancellation
drops child frames, writers and references; it does not release caller-owned
contracts or Store custody.

Convenience APIs and the Node bridge select their implicit evidence workspace
through `publication_evidence_workspace`. Its fixed 4096-slot allowance is
for private bounded stream buffers, in addition to the existing eight slots
per canonical node, with saturation at IntMax. Explicit preparation budgets,
canonical byte/node/depth limits and Compute/import capacity are unchanged.
Invalid node limits still select zero. The generated Node and RelA bridges
and public interface are updated from their authoritative sources.

## Independent boundary evidence

The authored 257-character Unicode Text plus supplementary character requires
14 wire-control transitions and peak 1038 private slots. Comparing two streams
requires 20 transitions and peak 2063. Quantum 1, 7 and 64 agree.
A wire budget of 1037 refuses without retained private frames.

The independently authored 64-NUL value encodes to 386 bytes and takes ten
wire-control steps. Exactly 386 bytes succeeds; 385 refuses even after a
previous mismatch. Canonical `null` uses the fixed independent SHA-256 vector.
Nested value mismatch, NULL/presence difference and partial cancellation
remain distinct from identity equality.

The two-name publication root fixture requires 249 transitions at all three
quanta. Its independent peak is 1052: root and stream frames, the bounded
buffer/fragment reservation, three pending emitter frames and one provisional
reservation. Exactly 1052 succeeds; 1051 refuses with the existing root
encoding cause. Cancellation preserves the original borrowed contract wire.

The small-node compatibility fixture succeeds with 256 nodes through public
capture issuance and evidence validation. An explicit 2048-slot budget
refuses the artifact-pair phase with its existing
`EvidenceInventoryMismatch("result_artifacts")` cause. This is not a claim
that every valid capture fits 128 nodes: the initial 128-node envelope was
correctly refused by its unchanged encoding limit.

The ordinary Host fixture executes a Values/filter/select producer and two
consumer Stages with real retained and publication Stores. It reads all three
independently named Results, comparing exact DESC order and hand-authored
Unicode/NULL rows. Fresh cancellation is delivered after positive root
progress before capture context preparation, or during embedded Receipt
checking before publication context validation. No publication is exposed,
cleanup returns retained resources, and Compute dispatch count remains three.

## Durable finalization race

Additional yields exposed a real existing concurrent finalization boundary.
Two callers can issue the next succeeded record before either physical
append. After the first durable append, the second Store transition check
rejects with `InvalidPublicationRecordTransition`, rather than the later
link/CAS conflict code.

The existing race fixture now synchronizes both issued records explicitly,
without sleeps, and forces that exact stale-transition refusal. The adapter
adopts it only when the common owner reports terminal success and the admitted
record names the exact same committed index. Store transition validation is
not relaxed; no new state machine, ledger or execution retry is added.

Negative cases keep a real unfinished finalization refusal observable, and
reject an admitted terminal success for a different index. Reconciliation
through the actual Store then completes the already committed outcome.
Removing the exact-index check makes the foreign-record negative case fail.
Private cursor cancellation remains separate from cancelling a durable commit.

## Executed checks

Commands use the repository-pinned Node and MoonBit environment:

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

Final source results and consuming artifacts are listed below.
Receipts remain in `_build/local-checks/attempts` and
`_build/focused-evidence`; later documentation-only commits do not relabel
these runs as new-SHA execution.

- Common JS: 271/271; `run-CZmDQm`, `focused-test-zPDmQu`.
- Release runtime build: 38 incremental tasks; `run-WBmj0w`. Both runtime
  roots come from the common tested source. These are checkout release
  artifacts, not pristine packed tarballs.
- Selected Node: 10/10 at the final Host source; `run-VUt0K8`,
  `focused-test-id7qNT`. Eight actual retained Host cases plus the portable
  control case and its nested cleanup case passed.
- Node/RelA bridge, Node Host and Workers fixture freshness checks passed.
  Four changed Node files pass syntax checks. Fourteen changed MoonBit
  sources match complete pinned formatter output. Commit subjects follow
  Conventional Commits and every message line is at most 72 characters.

A preceding final Node selection, `run-06ZmWF`, passed 9/10: the new root
cancellation fixture tried to schedule on its first poll while asserting
multiple polls. It now waits for a second observed root poll and keeps the
typed abort cause, nonpublication, no extra Compute and cleanup assertions.
The synchronization correction does not change production sources.

Earlier acceptance is not substituted for these final runs. Initial common
fixture diagnostics included an inaccessible test helper and two Debug/Show
diagnostic compilation mistakes; these were corrected. The original complete
Node selection passed its retained Host cases but failed the portable race.
The explicit synchronization reproduced that failure before the fix.
The initial small-node test used an envelope exceeding 128 nodes; its explicit
budget probe initially expected a generic cause instead of the existing typed
artifact inventory cause. These failures are retained as diagnostics, not
successful acceptance or grounds for weakening limits.

Two unpublished commits were recreated solely to wrap a 73-character body
line. Their trees and mapped parent relationship were checked unchanged.
Earlier receipts retain their original source SHA; no published history or
code was rewritten for that formatting correction.

## Remaining scope

Capture snapshot/dependency preflight and issuance inventories, evidence
suffix validators, scalar schema/unique-array checks and field-name
normalization still contain synchronous boundaries. The connected closed
contract objects use the existing fixed-field removal helper; generic large
object normalization is not closed here. Contiguous allocation latency is
also not guaranteed by logical frame accounting.

Blocking convenience APIs share the new algorithm but remain blocking.
Effectful asynchronous commit connection, explicit Native/direct execution,
all-target, packed/HTTPS and hosted required CI are unverified by this unit.
The admitted Model evidence regression is not a packed Model provider
acceptance campaign. Whole publication and whole retained Local completion
remain separate goals.

