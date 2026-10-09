# Selected completion metadata reuse

## Regression and existing owners

On base `2fa91dd62fc300f509687f34a9990a7d76c3e031`, the existing ordinary
Append -> Filter fixture rejected its independently specified work allowance.
The original 81/80 work, 10/9 workspace and 78 physical-work assertions already
exist before producer-read preparation #677. They remain unchanged.

Resumable completion preparation #749/#758 added 31 polls for `append_0`
and 28 for `where_1`. The chain correctly counted those productive polls.
Changing its counter or increasing the allowance would conceal the regression.
Instead, this correction removes repeated immutable metadata validation.

`value_contract.Fields` retains the aggregate UTF-8 name bytes measured by its
existing constructor, decoder or parameter decoder. Contract joins reuse that
quantity only after their existing exact-name check. `relation_schema.Schema`
retains the corresponding reference-spelling total, including qualified
prefixes. No normalization, second names array or metadata execution owner is
introduced. Nested child names do not enter their parent's aggregate.

The opaque singleton generated selection already binds its retained ID to the
exact selected node. Generated IDs are ASCII. Selected Append and Filter reuse
that proof, their exact schema, and its measured total in the existing trusted
completion cursor. All other operations retain their existing preparation.

## Policy, accounting and custody

The current entry limit and both target-name occurrences plus schema-name bytes
are checked on the first advance, before any input scan. Overflow-safe
subtraction preserves the exact policy. A prior permissive execution cannot
authorize a later stricter limit. Exact receiving-input ownership and current
availability remain checked independently at start and throughout execution.

Successful constant-time proof checking joins the original execution
transition; no name scan is executed without reporting its work, and no
chain/control/value charge is removed. Policy-admitted cursor phase 4 cannot
finish through the ordinary partial-preparation API. Each kernel later
transfers its already constructed canonical names array to the completion
port, and drops its own reference without clearing the transferred array.
Cancellation before transfer retains custody until confirmed cleanup.

Each existing Fields and Schema record gains one cached Int. The structural
census now includes these fields explicitly. They are persistent configuration
metadata, not zero-byte allocations. No per-field array is added. Existing
declared capacity allowances and workspace ceilings are unchanged; this source
census does not establish new Native allocation sizes or a whole-heap bound.
Historical source-bound Native receipts are not evidence for the changed layout.

## Focused evidence and remaining checks

The source patch is independently reviewed. Review caught and removed an
unrelated copying `kernel_body` classification probe; the final guard uses
allocation-free checked-operation accessors.

Patch SHA-256:
`1a6b4404de98078fd85505710e26c81a7edc2095d6b485116492c5e4851b847c`.
This was applied to the ongoing base-2fa91 integration working tree, not a
pristine published revision. The bounded JS gate with `--deny-warn` established:

- Original Append integration file: 11/12 passed (`run-DnToYM`,
  `focused-test-vyf6O1`). The unchanged 81/80, 10/9 and 78-work case passes.
  The sole failure was the independently diagnosed omitted 512-byte
  producer-preparation capacity term; the separate fixture correction adds
  the two documented handles without changing the production reservation.
- Selected Unicode/policy/custody cases: 7/7 (`run-aQY1CO`,
  `focused-test-F1KnzG`). These include actual backing-array transfer,
  150/149 byte admission, repeated tighter policy, pre-row refusal,
  cancellation before/after name population, revoked input and post-cleanup
  output readability. The selected non-Filter control retains scalar polling.
- Contract metadata provenance: 1/1 (`run-OGd6Ve`, `focused-test-334lRZ`),
  including all construction paths and nested parent/child quantities 5/136.
- Flat/scoped schema quantities: 1/1 (`run-24e2Fm`, `focused-test-8eX7Mq`),
  with independently fixed Unicode totals 134 and 279.

No full Core, Wasm/Native, packed/public Host, physical-byte correspondence or
hosted CI success is claimed by these focused receipts. The five separate
fixture/report/watchdog corrections and added structural-census tests still
need their own central verification. Current-policy removal, destructive
array-clear and cached-total corruption mutations should fail the corresponding
independent assertions; no mutation execution is claimed here.
