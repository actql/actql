# Native receipt and policy checkpoint controls

The seven original integration failures were rechecked after normally adopting
main `1b9f2b50f628dd7e14c8749f7f0b14b153f1d299` and its common keyed Source repair.
Diagnostic `run-TwxT0W` failed all seven; `run-pWAp40` independently reproduced
missing current receipt capability with the existing Native Source evidence API.
These attempts and all original failures remain failed evidence.

Six controls have independent contract corrections, with no product changes:

- The resident Source catalog and hand-assembled Native observation still used
  the preceding two-receipt contract CID. Sorted-key canonical JSON of the
  current normative contract is 7,219 ASCII UTF-8 bytes and hashes to
  `sha256:d3d2737da6d73801f85208a2cdfe50c412e9f7b24e8bf9807e6f804e11757dd7`.
  The complete historical contract body and CID are retained independently.
  Change only that capability declaration and oracle contract pin. Preserve
  every SourceView/schema, receipt/record, row, byte count, authorization,
  original-Run, settlement, cancellation and refusal assertion.
- Reconstruct the current policy Program from the existing independently authored
  generator, not from product output. The entire original offer/rate/capacity
  and assignment projection remains identical; only the Program definition CID
  and resulting policy projection CID change. Preserve the full historical body.

The added Native API counterexample confirms current capability support and
refuses the historical capability; it performs no database I/O. JS checks of
Native-named fixtures cover their portable Host doubles and contract plumbing,
not execution of a Native binary or external Python/Local/HTTPS installation.

`integration-receipt-oracle.test.mjs` independently hashes normative current and
historical JSON and requires byte-identical test bodies except the declared pin
replacement. The Python original test body must remain an unchanged prefix.
The existing policy generator remains the authority for its authored projection.

## Remaining original standard Host failure

The separate standard Host control still fails; it is not excluded and is not
claimed repaired by this unit. The original Program, Source data and limits are
unchanged. Dirty diagnostic `run-2WOEhE` obtained existing Owner facts:

- `Estimate(NoStrategy)` in mode 0, with all three Local rejection checks `None`.
- The sole candidate assessment rejects with `RetentionLimit`:
  transfer 30,000, retained 32,198,400, execution 45,370,624 bytes.
- The original ledger retention ceiling is 32,000,000 bytes and execution ceiling
  is 134,217,728 bytes. No ceiling, coefficient, input bound or expected output
  is changed. A owns the common capacity derivation investigation.

That diagnostic aggregate remained failed (exit 2) even though the six repaired
original cases and their refusal controls passed: JS 11 + 1 and independent
Node 3. The diagnostic overlay is preserved outside Git and removed from the
submitted product/test tree. Final clean-source checks are recorded separately.

Run `node reviews/2026-10-13-frontend-core-checkpoint/integration-receipt-prepared-checks.mjs`
with the checked-in Node/Moon pins: existing non-Heavy 60s/TERM5 guard only.
No full Core, new package producer, Hosted CI, Provider or installed E2E is part
of this unit. The original fixed full Core failure remains distinct evidence.
