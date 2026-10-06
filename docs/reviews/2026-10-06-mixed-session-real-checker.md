# Mixed Session acquisition through the executed checker

## Missing connection

The existing final tests execute Lean for the complete fresh catalog. The
selector and application tests also cover mixed acquisition, but with smaller
inventories or a controlled proof result. Those checks do not demonstrate that
the full mixed inventory survives application reconstruction, the executed
checker and the final certificate consumer together.

The new regression uses the existing final-test source and receipt fixture,
the current complete catalog, the real acquisition selector and verifier,
`checkApplications`, the pinned `checkPlan`, and `checkCertificate`. It changes
no production policy, workflow, registration or certificate schema.

## Preserved observations

- An unrelated documentation addition leaves the selected action inputs equal
  across two distinct fixture revisions. A `workflow_dispatch/main` original
  supplies only `mutations-js`; every other obligation receives a candidate
  receipt. The selector's producer and final validation each read ready evidence.
- The actual Lean process checks all requirements and applications, including
  the Events obligations. The final consumer binds its real input/output
  digests, the catalog and the original receipt digests. Original receipt bytes
  remain unchanged; relabeling reused evidence as candidate execution fails
  certificate correspondence.
- A manual feature-branch original and a PR original labeled `main` each fail
  with `Lean rejected action plan`. A missing runtime, compilation failure or
  timeout is not accepted as this expected refusal.
- A changed Session source first rejects the old reused application. Actual
  input comparison then makes the selector choose fresh without consulting
  ready evidence. Candidate receipts for the entire catalog pass the real
  checker and final certificate consumer.

## Trust and remaining acceptance

Source trees, receipt observations and the ready-evidence reader are controlled
test seams. Their labels do not establish GitHub provenance, actual mutation
execution or physical Host acceptance. The Lean process and production JS
selection/application/certificate code really execute; their result is a local
connection regression, not a new authenticated main original.

The earlier local isolated-image observations remain separately scoped. This
change does not rerun or replace them. Actual compatible main comparison,
ordinary-PR reuse, related-change operational execution and net runner savings
still require their own evidence. No origin timestamp is counted as saved
candidate time, and no Actions environment or CI-only guard is impersonated.

## Focused local command

Use the installed toolchain selected by `proofs/bounded-session/lean-toolchain`
on the normal PATH, then execute:

```sh
node scripts/local-checks.mjs test node --timeout-seconds 180 -- \
  proofs/ci-evidence/final.test.mjs \
  proofs/ci-evidence/check.test.mjs \
  proofs/ci-evidence/applications.test.mjs \
  proofs/ci-evidence/acquisition.test.mjs
```

The fixed source SHA, actual counts and bounded evidence location are recorded
in the PR after this command completes. Full proof, Core, packed and performance
campaigns are outside this selected check.
