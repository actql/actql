# Resumable Sequence positions and scratch reclamation

Implementation SHA: `9f330a419ab437eae223404fcef8479a19df0e2c`.
Dependency: #793 (`97ed00d0d37882107c09d3d2178e4a26d63b975e`), with
#787, #780, #774 and #769 beneath it. These dependencies are not assumed merged.

## Production boundary

A checked/lowered sixteen-event adjacent Sequence fixture demonstrated that
one `advance(1)` copied all selected positions and inserted the complete match.
The pre-change test failed exactly at the match-publication assertion (1 versus
0), not at preparation, input binding or expression evaluation. The receipt is
`run-9avlY6` / `focused-test-rVxPCe`; it records the parent HEAD with fixture-only
uncommitted changes. This is a kernel resume-boundary counterexample, not a
measurement of public cancellation latency.

The existing Sequence session now owns a borrowed source, a reserved destination
and a position cursor. Partial extension and independent match copying append
one position per physical resume unit. Capacity is reserved before insertion;
neither a partial match nor an incomplete output is published. Source arrays
remain owned by the existing selected/partial collections until copying or
physical stop settles.

Selected positions, per-group partials, row-match flags, predicate snapshots and
completed match positions drain through resume phases. Cleanup removes at most
64 algorithm-scratch entries per callback and retains the parent reservation
until reclamation finishes. Accepted output remains independently usable.
The provider checks `bounded_sequence_match_cleanup_pending`: the common
cleanup Bool means state changed, not necessarily that all cleanup is complete.
No replacement scheduler, cleanup owner, evaluator or public contract is added.

Logical control charges and the existing structural slot model remain unchanged.
The new copy/drain transitions report their actual physical work; they do not
round work down to satisfy the driver's quantum check. Normal Sequence work 642
and workspace 58, including their existing one-short cases, still pass.

## Independent acceptance

- Adjacent allow/disallow fixtures match all sixteen events with equal clocks
  and explicitly ordered identities. Subsequence allow/disallow uses four
  events to exercise the same copy owner without conflating combinatorial
  partial demand with the wide-copy counterexample. Quanta 1, 7 and 256 produce
  identical independently authored rows and logical control remainder.
- The wide sixteen-event allow/subsequence fixture retains its typed capacity
  refusal: 6,435 eight-position subsets alone need 51,480 position slots,
  exceeding the unchanged 10,000-slot test limit. Cleanup retains input custody
  and does not convert that refusal into a partial result.
- At the disallow copy boundary, independent live slots are
  `4 + 1 + 16 + 16 + 256 + 35 + 16 + 16 = 360`: input names, key, clocks,
  predicate containers/cells, output names, ordering and selected positions.
  The destination needs sixteen positions plus one match record. Limit 377
  reserves the destination; 376 fails with `Rows(RowLimit)` before any copied
  element or match insertion. This is the copy-boundary limit, not a claim
  about the entire sixteen-event output's peak.
- Private barriers deliver cancellation during partial extension, match copy,
  selected/group/match release and predicate-snapshot release. Inputs and live
  reservations survive the stop request and stop confirmation. Repeated cleanup
  removes no more than 64 scratch entries per attempt, eventually clears all
  scratch/reservations, and does not consume further logical computation work.
- The ordinary public Host uses a real retained Store for sixteen-event allow
  and disallow Programs. `published`, `consumed_a` and `consumed_b` must all
  contain exactly `[{id:1,value:16}]` with the expected nonnullable number
  schema. Request reuse adds no dispatch. A delivered positive-progress cancel
  keeps held resources before physical stop, leaves all Results unavailable,
  confirms stop and reclaims retained snapshots. This public barrier is not
  claimed to identify the private copy phase.
- Gate mutations remove required quantum/workspace/stop/cleanup/public roles
  or production copy/release/pending connections and must fail. These structural
  mutations supplement, rather than replace, the executed runtime cases.

## Executed checks

At the clean implementation SHA, the combined real Host/gate/index selection
passed **6/6** (`run-1x5KV3`, `focused-test-PfRxCY`):

```sh
node scripts/local-checks.mjs test node --timeout-seconds 120 -- \
  --test-name-pattern 'sequence position assurance|acceptance evidence index|evidence paths exist|public retained sequence (allow|disallow) position copies' \
  scripts/check-local-resource-accounting.test.mjs \
  scripts/pure-operation-inventory.test.mjs \
  adapters/host-node/public-property-name-retention.test.mjs
```

Only the two actual consuming runtime roots were built (`run-RyI2YA`, 39 tasks):

```sh
node scripts/local-checks.mjs build moon --timeout-seconds 120 -- \
  --target js --release --jobs 2 \
  src/client_values_host_abi src/connectors_builtin_node
node scripts/build-local-node-assets.mjs
node scripts/build-local-node-assets.mjs --check
node scripts/build-run-host-core-package.mjs --runtime-only
node scripts/build-run-host-core-package.mjs --check
```

The ignored consuming assets have SHA-256 digests:

- Local provider `connectors_builtin_node.js`:
  `682b09d4804dc778e60de85fe6b430cbaab615669803fa60394682ebcf2ecc46`.
- Run Host `client_values_host_abi.js`:
  `ae953e7d035039b0ece6fd1f6421114d95eb65ff314e034573111108ea3fb100`.

Other asset-generator roots reused existing artifacts. This is selected checkout
acceptance, not a pristine packed/all-root campaign.

Before committing, the affected JS core and managed/retained caller selection
passed **32/32** (`run-AairoM`, `focused-test-ThP2gD`). After adding the explicit
wide-subsequence refusal and per-cleanup entry/accepted-output assertions, the
final position fixture passed **5/5** (`run-mE1Sl9`, `focused-test-P1ZAOB`):

```sh
node scripts/local-checks.mjs test moon --timeout-seconds 180 -- \
  --target js --jobs 2 src/execution_relation/sequence_position_cursor_wbtest.mbt
```

These JS receipts record the dependency HEAD with a dirty source tree, not a
clean-HEAD Core execution. Earlier compile/fixture attempts remain recorded:
unused mutable fields, obsolete single-call cleanup assertions, independent
field-order construction and a combinatorial subsequence capacity refusal.
No product budget was raised to repair those attempts. Receipts remain under
`_build/local-checks/attempts/` and `_build/focused-evidence/`. Changed MoonBit
files individually match the pinned formatter; Node syntax, whitespace and
72-column Conventional Commit checks passed.

## Remaining work

This closes Sequence position copying and explicit algorithm-scratch collection
walks, not all Local retained execution. Installed availability callbacks,
Native capacity correspondence and integration of the parent stack remain.
The common admitted-output buffer's cancellation/disposal is not made resumable
by this change and remains a distinct boundary to audit; this record does not
claim that every possible cleanup root traversal is bounded.

Wasm, Native, packed/HTTPS, full Core, proof, performance and complete Store-fault
suites were not rerun. Draft CI is preparation, not merge verification.
