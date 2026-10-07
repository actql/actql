# Incremental Local dispatch scratch retirement

Implementation: `868a7fefa0a1d5d627c92c25a607f75818bcaa3e`.
Adopted main: `f39590a3b8f71340e6ddaa4c7e3de6c1bd7f41d5`.
The unit started from accounting evidence #822. That parent was subsequently
merged and adopted; the final PR targets main with no unmerged dependency.

## Existing boundary and change

`release_owned_scratch` previously walked all bridge handles, retained imports,
receiving reads, finalization CIDs and identity issuers synchronously. Its
installed `scratch_released` witness then scanned the same collections again.
This was an unbounded source-level collection walk, not a measured public Run
stop-delay counterexample.

The existing driver retains a private phase/index cursor. Each release callback
retires at most 64 collection entries or phase transitions, including the
boundaries of empty collections. Pending roots remain in the original arrays;
there is no replacement custody owner, ledger or provider. The witness reads
the completed cursor and existing fixed-state conditions rather than rescanning
all collections. It does not initiate cleanup or alter work.

Provider stop and successful provider cleanup still precede dropping its root.
Cumulative work is cached first. Active/reentrant callbacks block retirement.
The common reservation owner continues to retain scratch while the witness is
false and only returns it after retirement. Accepted output and input producer
storage are not disposed by this cursor. Failed or unpublished aliases retain
their existing disposal conditions. No public API, CID, logical work rule or
operation limit changes.

All bridge/import writes now reject settled or disposed execution as well as
cancellation. In particular, an import handle detached during successful
settlement cannot open a new importer and repopulate already retired roots.
These lifecycle checks add no authority; exact binding, availability, transfer
accounting and admission remain in the existing owners.

## Executed evidence

At clean source `df8dd117cb06d9de681bfa454f1d9e5b8b43dae5`:

```sh
node scripts/local-checks.mjs test moon --timeout-seconds 120 -- \
  --target js --jobs 2 \
  src/connectors/local/driver/scratch_retirement_wbtest.mbt \
  src/query_integration/managed_import_release_wbtest.mbt \
  src/query_integration/local_managed_values_wbtest.mbt
```

Passed 31/31: `run-JbSMaq`, `focused-test-tHaahG`. Six private cursor cases
check a 70-root pending slice, issuer slicing, empty input, the final phase
boundary at 64/65 transitions, reentrant callback custody and late-write gates.
Actual installed-driver callers retain successful output, producer survival,
cancel/stop ordering, cumulative work and idempotent reservation release.
The private root counts are not a claim that a public Program has 70 ports.

The implementation was amended before publication to add one missing source
mutation guard. Only the two source-guard JavaScript files changed between that
SHA and `868a7fefa0a1d5d627c92c25a607f75818bcaa3e`; all MoonBit, adapter
and runtime inputs are byte-identical. The earlier JS execution is not
relabeled as a later-SHA run.

Only the two consuming runtime roots were built at that earlier clean SHA:

```sh
node scripts/local-checks.mjs build moon --timeout-seconds 120 -- \
  --target js --release --jobs 2 \
  src/client_values_host_abi src/connectors_builtin_node
node scripts/build-local-node-assets.mjs
node scripts/build-local-node-assets.mjs --check
node scripts/build-run-host-core-package.mjs --runtime-only
node scripts/build-run-host-core-package.mjs --check
```

Build receipt: `run-Ov1ZDe`. Both generated asset comparisons passed. Runtime
bundles remain ignored. Other runtime roots reuse their existing artifacts;
this is not a pristine all-package or packed assembly.

Consuming asset SHA-256 values:

- Local provider: `833bd9e113bc6ece335042fdfc339eaa3d0a6bb7a369515b4a1f6e184d6541bb`.
- Run Host ABI: `226557953b53c84cbf9076f090075d02ecd02199b42dd1307eaf22f90ee85aba`.

At the clean implementation SHA:

```sh
node scripts/local-checks.mjs test node --timeout-seconds 120 -- \
  --test-name-pattern 'public retained Values completion names|public retained Append completion names|public retained Cross Join completion names|source rejects|current driver/common' \
  adapters/host-node/public-property-name-retention.test.mjs \
  proofs/relation-pipeline/capacity/parent-control/driver-retirement.test.mjs
```

Passed 20/20: `run-dZOrbc`, `focused-test-zaHZ1t`. Three real-Store public
Host cases check exact producer/two-consumer Named Results, request reuse
without additional dispatch, delivered cancellation after progress, custody
before physical stop and final snapshot release. Seventeen source/overlay
guards check stop, cleanup, work caching and common reservation ordering, plus
the cursor construction/slice/witness and late-write boundaries. Admitting a
Native overlay's construction is not execution of Native code.

The source-guard fixtures now require the mutation target to be unique before
entering the expected-rejection assertion. A missing target can no longer pass
by throwing inside `assert.throws`. Whitespace changes do not hide the target.
The common reservation retirement body is unchanged and still checked exactly.
This is not a new allocation-byte model or implementation-refinement proof.

## Preparation failures and remaining work

Two earlier dirty-source MoonBit attempts failed compilation in the new fixture:
`run-V8J8EH` used an obsolete debug trait; `run-0gH9DO` put raising assertions
inside a nonraising callback. Both are preserved, not counted as passed tests.
The corrected reentrant fixture captures facts and asserts after callback exit.
An earlier dirty-source guard selection passed 35/35 (`run-SwA7tV`); it is
distinct from the later fixed-SHA source selection.

The first public attempt, `run-ZbVpgM`, failed before Host execution because
borrowed dependencies resolved an older `client-wire` without
`validCancellationLookup`. Its seventeen source guards passed, but the command
failed. No product fallback or export was added. Private, ignored SDK and Run
Host dependency installations now link to this checkout's canonical
`packages/client-wire`; the shared root dependencies were not modified. The
second public attempt above passed with those explicit source-local dependencies.
This remains checkout-boundary evidence, not packed distribution acceptance.

## Final main integration

After #822 merged, main `735ac73c5519753f77de31c26d6233ffc015c088` was
normally merged without conflicts. Integrated source:
`71289a8cdb5bd9948499dabcf83a074d69e516ed`. The Local driver/cursor and
retirement guards are byte-identical to the implementation above. The merge
also preserves current Graph Frontend and SDK cancellation changes.

The same two-root build command passed (`run-F8b0Wb`), followed by the same
asset generators/checks. The same focused public/source-guard command passed
20/20 (`run-I7DtDg`, `focused-test-ddvWGq`) at this clean integrated SHA.
The Local provider asset is now
`58e332f4b86c6b5abc9573e5acf586e36ea23eca9f9693d2b54aa4b72c6f2471`;
the Run Host ABI asset remains
`226557953b53c84cbf9076f090075d02ecd02199b42dd1307eaf22f90ee85aba`.
The earlier 31-case JS selection remains evidence at its original SHA; it was
not relabeled or rerun as an all-Core integration campaign. The later record
commit changes documentation only and does not replace these source identities.

Before the first push, five unpublished commit messages were wrapped to the
repository's 72-character limit. Every tree and exact parent correspondence
was checked unchanged; no published history or code was rewritten. The executed
implementation `868a7fefa0a1d5d627c92c25a607f75818bcaa3e` maps to published
`9d1c3381243484bff7365de22b8054e98e9fedaa`; the integrated executed source
`71289a8cdb5bd9948499dabcf83a074d69e516ed` maps to published
`4c477fba0dae106f60857718a9860d5ced87b7f8`. Those checks remain tied to the
original observed SHAs; the mapping establishes identical source, not another
test execution or CI success.

Installed availability callbacks, cancellation/disposal walks over input
handles, retired-Carrier walks, other scratch collections and Native physical
allocation/reclamation correspondence remain distinct. This cursor proves a
collection-entry bound, not a GC/destructor or wall-clock latency bound. Fixed
driver metadata continues using the existing envelope; full physical-byte
correspondence is not established here. Wasm/Native, full Core, proof campaigns,
packed/HTTPS, performance and CI execution were not rerun. The whole retained
Local goal remains open.
