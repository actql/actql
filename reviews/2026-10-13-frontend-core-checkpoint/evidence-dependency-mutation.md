# Keep the evidence-dependency refusal adversarial after contract adoption

The original assigned `query_planning/evidence_contracts_wbtest.mbt:80` failure
is a test defect, not a verifier accepting an altered acquisition dependency.
The negative test replaced a historical acquisition CID substring which no
longer occurs in the generated full evidence fixture. Its supposed changed
input was consequently identical to the valid original.

Read `dependencies.query_acquisition.cid` structurally from the independent
fixture JSON and replace only that slot with the all-zero SHA-256 value. Assert
that the complete serialized value changed before checking the exact existing
`UnsupportedEvidence` refusal. Keep the schema-only refusal, original full
bodies, aggregate byte/node bounds and verifier unchanged. No observed product
hash is used to generate an expectation.

`run-QqowxR`: selected planning/Carrier checkpoint diagnostic, 13/23 passes,
ten original failures. The mutation probe's first two attempts failed compilation
at Json constructor references (`run-XAlIiF`, `run-uSwH48`); executed cases zero.
After using the pinned Json public factory, `run-1LcdOf` passed the actual two
evidence-contract tests. Final clean-source results are reported separately.

The rest of the Carrier work/analytic/Graph plan failures in that selection are
not closed by this change. Do not lower work accounting or replace independent
work budgets with measurements. Original G full-Core failure remains unchanged.
Installed public E2E: **0**; full Core, Heavy, provider, package campaign and
Hosted CI: **0**.

Reproduce with the existing pinned, nonzero, non-Heavy 60/5 guard:

```sh
node reviews/2026-10-13-frontend-core-checkpoint/prepared-checks.mjs \
  src/query_planning/evidence_contracts_wbtest.mbt
```

Also run the existing read-only `scripts/check-query-evidence-fixtures.mjs`
freshness check. It verifies the full normative generated bodies; it does not
establish public Host execution.
