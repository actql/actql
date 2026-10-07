# Resumed retained binding and commit inventories

## Completion unit and dependency

The existing Effect-free retained publication commit preparation now polls
durable binding inventories and request/index references. This closes those
traversals in the connected JS Host path, not all publication metadata or the
whole retained Local objective.

The tested clean source is
`549cf972ef68a1d703f99628377699f8fded64e9`. PR #936 remains an unmerged
prerequisite at `eb9d84996d12bb333b2a9e9ee0e337b24433f9cd`; the child PR
targets `feat/local-bounded-publication-inventory` until that prerequisite
reaches main. The inherited main is
`2d38f1ccf8134ebb96446ef9cb1e53767a704200`. The parent formatting correction
was normally merged without conflicts. Subsequent record-only changes do
not relabel execution receipts as tests of a later source.

## Existing owner connection

`DurableBindingPreparation` borrows admitted contracts. Duplicate binding
and definition identities, exact Artifact lookup, ordering/retention
membership, bound fields and index membership each advance through explicit
cursors. Index strings are validated before cardinality, preserving typed
refusal precedence. No whole inventory copy, filter or sort is required.

`PublicationInventoryPreparation` reads immutable canonical entries and
matches exact definition references. Long Result names use the existing
64-unit UTF-16 fragment comparator, with an offset retained between polls.
`PublicationReferencePreparation` polls that child and checks request,
attempt and index bindings. Namespace equality uses the same raw UTF-16
comparison; configuration normalization is not applied to these values.

`PublicationCommitPreparation` connects both children after Result evidence
and before final completion. It supplies remaining workspace, accounts for
the peak and retires each private child on completion or refusal. Cancellation
releases private references only; admitted inputs and Store custody remain
with their existing owners. The inventory child frame is reserved before
construction, including the one-short rejection path.

Explicit blocking callers drain these same private owners. They do not select
a second validation algorithm or a fallback on the connected Host path. No
wire shape, schema, CID preimage, admission rule, ledger or commit authority
changes. Fixture phase labels are observations, not authority.

Existing commit-first reconciliation still validates a durable committed
outcome even when the request is already aborted. Private cursor cancellation
is not evidence of aborting a durable commit. Fresh precommit cancellation
remains at the existing context/row validation boundary.

## Independent acceptance

For N bindings in the authored fixture's natural order with shared retention,
the independent successful control total is:

```text
4*N*N + 14*N + 5
```

N=2 requires 49 transitions at quantum 1, 7 and 64. N=32 requires 4,549 at
quantum one. The private binding frame reserves sixteen slots: sixteen
succeeds, fifteen refuses with `CommitEncoding` and leaves zero live slots.

For request inventory validation, the independent total is:

```text
N*N + 2*N + sum(name comparison fragments) + 2
```

The full reference check adds eleven fixed transitions and the namespace
comparison fragments. Two names requiring five fragments each, and a
five-fragment namespace, require 36 transitions at quantum 1, 7 and 64.
The parent and inventory child require 24 private slots. A limit of 23
refuses in the first poll, before creating the child. These are logical
workspace reservations and control transitions, not physical allocation
latency guarantees or changes to Compute's contractual logical work.

Common regressions cover permuted inventories, missing/duplicate/extra
references, foreign bound fields, non-string index entries and typed failure
precedence. Partial index/name/namespace cancellation drops private state,
leaves borrowed contract bytes unchanged and can be repeated safely.
Long-prefix mismatches retain the exact namespace or inventory cause.

The private reference fixture uses distinct admitted CID tokens to isolate
reference traversal. It is explicitly not a complete Run evidence chain.
Corruption probes below admission are not valid public index fixtures. The
actual Host cases below supply the real Receipt and Captured Run owners.

The normal Program has a Values producer with filter/select and two consumer
Stages, using real retained and publication Stores. Its namespace contains
4,097 composed Unicode characters plus a supplementary character. Success
requires multiple pending polls in both binding and namespace phases at
quantum 32, then reads exactly the producer and both consumer Named Results
against fixed Unicode/NULL rows and exact ordering.

Existing cancellation cases deliver abort after positive context/row
validation progress, prevent contract writes, attempt creation and public
index creation, and finish with zero retained resources and no extra Compute
dispatch. Portable control coverage keeps committed replay under an already
aborted request and concurrent cleanup reconciliation.

## Executed verification

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
moon info --target js src/run_publication
node scripts/connector-node-bundles.mjs
node scripts/node-host-fixtures.mjs
node scripts/workers-fixtures.mjs
node --check adapters/connectors/duckdb/node/test/retained-values-chain.test.mjs
```

At the clean source above:

- Common JS: 263/263. Bounded receipt `run-USSUrb`; focused receipt
  `focused-test-TdGVnh`.
- Release runtime build: 38 incremental tasks; receipt `run-jjGz1J`.
- Selected Node: 8/8, with seven top-level cases including six actual retained
  Host cases and one nested cleanup case. Bounded receipt `run-3EVapM`;
  focused receipt `focused-test-MLM6pP`. These consume checkout release
  runtimes built from the same source, not pristine packed tarballs.
- Selected API generation, Node/RelA generation checks, Node Host/Workers
  fixture freshness and Node syntax passed without tracked changes.
- Eight affected/current dependency MoonBit sources match complete stdin
  output from the pinned formatter, invoked separately per file.

Receipts remain under `_build/local-checks/attempts` and
`_build/focused-evidence`. Earlier `run-CR0jAk` passed 261/263 because the
negative fixture incorrectly added an already-existing field instead of
replacing it; that helper was corrected before final verification. An
automatic permission-review timeout did not create a process or execute a
check; the one permitted retry produced the successful common receipt above.
Neither incident is reported as successful acceptance or a product failure.

## Remaining boundaries

Computation metadata preludes, scalar schema/unique-array checks, field-name
normalization, issuance-side inventories and contiguous allocation latency
still have synchronous boundaries. Blocking issuance callers now share the
inventory algorithm but are not thereby asynchronous. Effectful commit
driver connection, explicit blocking Native/direct callers, all-target,
packed/HTTPS and hosted CI acceptance are not established by these checks.
No product capacity or semantic limit has been weakened. Whole publication
and whole retained Local completion remain separate goals.
