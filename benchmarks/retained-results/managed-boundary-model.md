# Limited managed boundary model verification

Date: 2026-09-16.

The standalone Lean model in `proofs/managed-retained` checks 15 named theorems
and executable examples with Lean 4.30.0-rc1. Run:

```sh
node proofs/managed-retained/check.mjs
```

The check passed. Every named theorem's axiom audit contains only Lean's
foundational `propext` and/or `Quot.sound`. The checker rejects unfinished proof
terms, custom axioms and unchecked native decisions, and treats warnings as
errors. No AoA/Smooth theorem coverage is claimed.

Coverage includes required evidence/identity before completion, subject and
issuer scope, bounded pin admission, live-pin reclamation exclusion, irrevocable
revocation along modeled traces, historical completion preservation, and a
universal-bound preservation rule for selection. Evidence truth and physical
actions remain trusted model inputs; the README lists the exclusions.

This supplies a limited formal model for part of Q2, not executable refinement
or complete new-profile conformance. Actual diagnostic ordering, view-rule
composition, delegated lifetimes and semantic execution still require their
independent implementation tests and additional coverage. It changes no wire,
CID preimage, contract pin or runtime path. There is no performance claim and
no new 1 GiB / 27-case benchmark result in this step.
