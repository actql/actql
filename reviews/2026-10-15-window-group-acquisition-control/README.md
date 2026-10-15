# Window-group JSON acquisition control correction

The first JSON control in the original installed `window_group` cohort was
rejected before Source I/O. This was an acquisition-profile mismatch, not an
observed window or aggregate result failure. The shared contract
`spec/contracts/actql-query-acquisition.json` declares
`exclusive_finite_relation_scan_filter_select`; the authoritative derivation in
`src/sourceview_resolution/query_acquisition.mbt` requires that exact exclusive
Filter followed by Select. See also the boundary table in
`docs/design/query-physical-strategy.md`.

The original independent JSON capture used only Select. The three JSON controls
now explicitly author a literal-true Filter followed by their original Select.
This predicate preserves every row, including NULL-bearing rows and duplicates.
The Source supplier, complete extent, downstream window and aggregate arguments,
column order, expected values and schemas, bounds, and nine-normal/nine-refusal
inventory are unchanged. SQL and AQL-text are byte unchanged. No compiler,
Common Owner, acquisition classifier, runtime, parameter or limit is changed.

`preimages/window-group-source-input.mjs` retains the complete original fixture
at `1f70a6d84851712e4b541238bae9571c168cdc96` (unchanged from `ef5606fe`).
The independent Node regression reads the declared acquisition contract and
compares every corrected Program against that preimage after removing only the
explicit identity filter. It also compares all expectations and textual cases.
Expected rows or schemas are never generated from product output.

## Evidence and qualification

Original normal four-package source `ef5606fe2a598fbb43e89ca53354088bd4c505fc`,
manifest `083c3642b0d8e5392fa89d437ca3d6a8e4b92b0e433efd7537756fe8e4b28f09`:

- Physical cohort `run-IOh9et` failed on the first JSON case on both Local and
  HTTPS, with zero completed normal/refusal cases. Its Run/DB, raw logs and
  artifact inventory remain retained outside this change.
- Pure diagnostic `run-T09CST` prepared the original Program but obtained
  `ClientLocalQueryIssue.Sequences` from query-requirement preparation.
- Pure differential `run-danFk2` executed one Node test: the original acquisition
  returns `UnsupportedAcquisition(UnsupportedShape)` and the explicit-filter
  control prepares its original query requirement successfully. Host, Source,
  DB and Run operations are zero. This is not runtime window-group execution.
- The first differential attempt `run-nzQrE2` failed because its diagnostic
  assertion incorrectly represented a payload-free MoonBit enum as an object.
  Its original script and failure are retained; no product change fixed it.

Regression source `b2a245d9cd09a5a4fa49dd53bff5c5ea542ad2f5`:
`run-sjb7BO` on pinned Node 22.22.0 executes eleven tests: ten pass and the new
capture-shape assertion fails. An earlier identical failure `run-LW1Px3`
selected Node 22.23.2 through PATH; it is retained with that distinct toolchain
qualification.

The existing bounded recipe is:

```sh
node reviews/2026-10-14-window-group-release-matrix/prepared-checks.mjs <clean-sha>
```

It uses the original non-Heavy 60-second/TERM-five-second guard and 30-second
focused Node child. Corrected-source Local/HTTPS execution is still pending a
matching normal four-package cohort. No pure or fixture test is a public E2E
PASS, and the original physical failure is not rewritten as success.
