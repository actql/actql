# Resumable retained COUNT and Sequence metadata

Implementation SHA: `2b0717e9b3154fe48b9b7e9c4de4884b5dcc2699`.
Dependency: #787 (`31543c5c154352c3b91e46577736357d20582f1f`), with
#780, #774 and #769 beneath it. These dependencies are not assumed merged.

## Production boundary

COUNT prepared name maps with whole-string hashing and charged complete names
inside one resume. Sequence resolved columns with whole requested/candidate
spellings, hashed predicate bindings and allocated pattern labels plus suffixes.
This is a source-audited boundedness gap, not a measured public stop-delay result.

`bounded_global_count.mbt` now borrows checked schema spellings, compares through
`RowMetadataLookup`, and reuses `RowNameCharge` for control and Value accounting.
The immutable Schema constructor rejects duplicate reference spellings; the
opaque checked count profile owns aggregate alias validity. Removing the maps
does not remove input binding, availability or output admission checks.

`bounded_sequence_match.mbt` uses `ChargedRowMetadataLookup`, keeps charged
indexed predicate snapshots and calls the existing expression frame owner.
Pattern output roles compare a virtual label/suffix in 64 UTF-16-unit fragments;
the existing inline text-charge cursor retains original UTF-8 logical costs.
No normalization, secondary evaluator, scheduler, identity or public API is added.

COUNT charges a spelling once, independent of lookup candidate count. Sequence
retains its prior per-candidate requested/candidate charges. Cursor work is not
rounded away. Predicate tuples reserve slots before insertion; their borrowed
cells survive until the expression settles or confirms cancellation. Cleanup
closes pending cursors once and does not dispose accepted output custody.

## Independent boundary evidence

- COUNT metadata for the one-key `id,n,present` fixture costs 28. Replacing `id`
  by a 136-byte Unicode spelling costs `4 * 136 + 20 = 564`. Exact and one-short
  preserve typed `Rows(RowLimit)` behavior.
- COUNT metadata uses twelve slots: two input ordinal/name entries, one key,
  six aggregate entries and three output columns. One-short fails before
  completion; cursor ownership overlaps an unfilled metadata entry.
- COUNT input Value names cost `2 + 128 + 4 + 2 = 136` bytes. The output adds
  `n=1` and `present=7`, totaling 144. Exact succeeds; 135 input bytes fail with
  `InputLimit`, and 143 output bytes fail with `Capture(CaptureLimit)`. Pending
  name scanning does not partially commit the atomic Value name charge.
- Sequence's long-key resolution costs
  `3 + 4 * 137 + 7 + 13 + 11 = 582`; 581 fails with `Rows(RowLimit)`.
  Empty input reserves fourteen metadata slots plus one pending lookup slot.
  Workspace fifteen succeeds; fourteen fails at that lookup boundary.
- Existing complete-operation limits remain unchanged: COUNT work 37/68/35
  for global/keyed/count-if profiles; Sequence work 642 and workspace 58.
  Their existing one-short fixtures also passed.
- Quanta 1, 7 and 256 yield the same hand-authored rows and logical remainder.
  Private cancellation barriers reach COUNT input lookup, aggregate/output
  preparation and input/output Value names, and Sequence lookup, predicate
  snapshot, output label charge and virtual output comparison. Stop retains
  borrowed inputs; cleanup and repeated cleanup reclaim cursors and workspace.
- The ordinary public retained Host executes long actual input names and long
  output aliases. It reads exactly `published`, `consumed_a`, `consumed_b`,
  compares ordered rows and schema, reuses requests without more dispatch, and
  confirms physical stop and final reclamation after delivered cancellation.
  This public positive-work barrier does not identify a private metadata phase.
- Required operation-specific roles and production lookup/charge/cleanup
  connections are mutation-checked; missing evidence or connections fail.

## Executed checks

At the clean implementation SHA, the following combined Node selection passed
**8/8** (`run-h5UVFg`, `focused-test-gDXR3g`):

```sh
node scripts/local-checks.mjs test node --timeout-seconds 120 -- \
  --test-name-pattern 'compound metadata|acceptance evidence index|evidence paths exist|public retained (COUNT|sequence) (source metadata|completion names|compound completion names)' \
  scripts/check-local-resource-accounting.test.mjs \
  scripts/pure-operation-inventory.test.mjs \
  adapters/host-node/public-property-name-retention.test.mjs
```

The clean source's two actual Host runtime roots built successfully
(`run-ZHftGz`). Both existing asset generators and their read-only checks passed.
The ignored consuming assets have SHA-256 digests:

- Local provider `connectors_builtin_node.js`:
  `0b194001c3f0333bf948a99df335008096d8e4e87ecf4e771a4d9d568b9fc4ac`.
- Run Host `client_values_host_abi.js`:
  `ae953e7d035039b0ece6fd1f6421114d95eb65ff314e034573111108ea3fb100`.

This proves selected checkout-runtime acceptance, not a pristine packed campaign
or freshness of every runtime root.

Before committing, the COUNT, Sequence, metadata and shared expression-frame
selection passed **44/44** (`run-ADd5UX`, `focused-test-ABNo0O`). After adding
the final Value-budget/quantum checks and formatting, the final metadata fixture
passed **8/8** (`run-sPqxWm`, `focused-test-r7q3vs`). Those receipts record the
dependency HEAD with a dirty tree, not a separate clean-HEAD JS execution.

```sh
node scripts/local-checks.mjs test moon --timeout-seconds 180 -- \
  --target js --jobs 2 \
  src/execution_relation/count_sequence_metadata_cursor_wbtest.mbt
```

An earlier Value-name fixture miscounted the independent UTF-8 spelling by two
bytes (`run-7gXYOJ`, 7/8); the corrected explicit byte formula passed. A diagnostic
fixture compile error (`run-tgSHNY`) is retained separately. An initial sandbox
launch could not perform the wrapper's process-group ownership inspection and
did not execute tests. No product limit was enlarged to repair these attempts.
Receipts remain under `_build/local-checks/attempts/` and
`_build/focused-evidence/`. Changed files match the pinned formatter individually;
Node syntax, whitespace and 72-column Conventional Commit checks passed.

## Remaining work

This closes COUNT/Sequence name processing, not all Local retention. Sequence
still copies partial/match position arrays and explicitly walks their collections
in cleanup; those algorithmic traversals need a separate bounded owner unit.
Installed availability callbacks and Native capacity correspondence also remain.
Wasm, Native, packed/HTTPS, full Core, proof, performance and complete Store-fault
suites were not rerun here. Draft CI does not establish merge readiness.
