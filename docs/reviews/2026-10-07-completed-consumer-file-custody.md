# Completed consumer output custody

A retained-input consumer used the standard captured Compute owner without its
physical output-storage hook. Its completion could therefore be saved without a
`NativeOutputFileCustody`, although the equivalent producer already retained a
file. Losing the consumer holder then lost the output needed for restoration.

The resident consumer now supplies the existing retained-task file owner to the
standard output exporter. It saves the exact dispatch's sealed file custody in
the existing execution journal before completion. Existing reader, release and
physical cleanup owners retain their responsibilities; the receiver Transfer
holding remains separate from the consumer output and borrow.

The captured-run factory has an optional storage argument, matching the existing
standard factories. No wire, identity domain or stored-record format changes.
The resident consumer requires its configured retained-output root. Missing or
failed storage does not authorize another Compute entry.

## Focused Native evidence

Use the pinned toolchain and a matching DuckDB library. The existing signed
fixture runner now also selects this consumer boundary:

```sh
ACTQL_TEST_DUCKDB_LIBRARY=<matching-library> \
ACTQL_TEST_SCRATCH_ROOT=<owned-scratch-parent> \
node scripts/test-native-completed-restoration.mjs --consumer-custody \
  -f '*producer holder*consumer*'
```

The runner selects Native with `--strip`, a 180-second bound and the existing
nonzero-test guard. Missing DuckDB prerequisites fail rather than skip. The
signed bundle is an opaque test component; these cases execute the actual Native
Source, Compute, Transfer and journal owners, not a deployed Site binary.

The three cases cover normal completion, cancellation before consumer entry,
and output-storage failure after consumer entry. Normal completion verifies the
independent `[{"id":3}]` result, original custody through a fresh journal
connection, file retention while a Result reader is live, and file absence after
formal cleanup. Repeated execution and close do not duplicate Compute or return
the independent receiver reservation early. Storage failure retains the original
execution responsibility and can close it without another Compute entry.

## Remaining recovery boundaries

This change makes future consumer completions durable. It does not create missing
custody for an older completed consumer, restore a holder, issue an Output report,
or establish Cloud publication/release acceptance. Existing failed Run evidence
and its pending Output/cleanup responsibilities must remain protected. Recovering
those responsibilities requires the exact original materials and existing
owners; Source or Compute replay is not a substitute.

The full Native/portable suites, formal Cloud package adoption and Preview
acceptance are separate checks. Generated standard-host interfaces were produced
with the existing `moon info` generator for JS, Wasm and Native.
