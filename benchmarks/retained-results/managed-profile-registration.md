# Managed retained profile registration

The Q1–Q11 design is now registered on `refactor/retained-execution` as
`actql-managed-retained-execution/0.1`, owned by
[execution](../../docs/spec/execution.md#managed-retained-execution).
This is contract work, **not a new-profile runtime or performance result**.
Main's `3820ea11` checkout and the existing acquisition contract bodies are
unchanged by these branch-local edits.

## Registered boundary

- One managed Run, including accepted local execution-process delegation.
- Admitted obligations define success; unknown future capability requests can
  fail independently of earlier valid completion.
- Existing logical preimages remain unchanged. Required identity is established
  by its deadline; unrequired identity need never be computed.
- Establishment and source availability are separate axes. Their diagnostic
  JSON grants neither issuance nor completion authority.
- The physical manifest pins interpretation and ordered chunk occurrences;
  its digest is distinct from logical content identity. Runtime count, codec,
  integrity and conversion checks remain necessary beyond JSON shape.
- Finite inclusion/view rules, bounded composition, diagnostic preservation,
  quantity-specific accounting, authority/pin/cancellation/reclamation,
  relocation and scoped issuance follow the agreement without process-local
  or projection-only narrowing.

The execution owner imports the complete machine contract and both closed
schemas. Document dependency CIDs and requirement fingerprints were updated
with the existing metadata generator; added requirements remain `pending` for
implementation evidence. Canonical fixture generation independently covers
the newly imported bodies. No old observation, process-evidence, two-receipt
or Result Artifact shape is changed to allow absent/dummy content identities.

## Evidence and remaining implementation

`scripts/managed-retained-contract.test.mjs` checks twelve independently authored
identity-state examples, explicit supported scope, unchanged legacy contract
pins, and positive/negative manifest shapes. Reordered chunk occurrences change
the manifest identity; repeated occurrences remain valid. A deliberately
shape-valid/count-invalid example documents the limit of schema acceptance.
These tests do not run a new-profile execution or prove an issuer truthful.

The later
[managed product evidence-reuse checkpoint](managed-product-evidence-reuse.md)
does run one finite product path through the registered profile. A two-column
checked filter/select chain publishes two successive managed results while
transferring exact selected measurements and performing zero repeated Core
value admissions. That closes one concrete part of item 2 below; it does not
make the complete conformance list true.

Verification passed: four independent contract tests, `npm run check:docs`,
three-target MoonBit checks, and `canonical_json` tests on JS/Wasm/native
(384 each), plus metadata, document-link, format and diff checks. The fifteen
new execution obligations remain pending runtime evidence in the registry.

The next runtime integration must replace the mandatory canonical receipt in
`AdmittedOutputStreamReceipt`-based retained custody with an explicitly selected
managed completion path, rather than weakening the old path's comparisons.
It must connect the registered manifest to owned generation/attempt/codec/view
binding in both Local and admitted DuckDB delegation. Existing old-contract
measurement reuse is useful but does not implement this change.

The following completion evidence is still missing:

1. Product selection/admission of the new profile, subject-limited issuance,
   closed identity states and legacy dependency-closure conversion.
2. Broader supported projection/rename/derive/sort/take chains with multiple
   consumers, and repeated use of newly validated join/group output, without
   unnecessary full conversion or repeated validation. A finite two-column
   filter/select chain is now connected and measured in the product Host.
3. Managed delegated pin/use/stop/reclaim and independent relocation with
   negative race, stale attempt, corruption and budget fixtures.
4. The limited formal model, declared trust boundary and checked bridges for
   any claimed application of existing mechanized theorems.
5. Completed independent same-obligation comparator and the unchanged formal
   1 GiB / 27-case acceptance runs, plus separately registered new-profile runs.

The full goal remains open until these paths and measurements are verified.
