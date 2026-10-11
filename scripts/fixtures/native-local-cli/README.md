# Native Local CLI fixtures

`source-program.json` is the authored Source → filter/select → filter/select →
Named Result fixture. `source-expected.json` contains independent data, rows,
columns and schema. The amount column includes NULL; the single expected row
does not establish ordering for a multi-row result.

`source-environment.json` retains the actual Source Data Policy original with
unknown classification. `read-installation.json` explicitly selects that same
Policy for the `answer` Result, `inspection` purpose and `jsonl` stdout sink.
Its finite byte/use/expiry settings are independent of submit permission and
do not reclassify the Source. The existing grant issuer performs admission.

The CLI process harness is prepared in `scripts/test-native-local-source-result.mjs`.
It never builds an artifact, downloads dependencies or starts a Node Host. A
light fixture preflight does not execute Native or establish public acceptance:

```sh
node scripts/test-native-local-source-result.mjs --preflight
```

For a separately allocated physical verification window, select a formal Native
CLI artifact for the exact clean source HEAD, an installed DuckDB Node API
package for synthetic database setup, and the actual Native library identifiers:

```sh
ACTQL_TEST_PRESERVE_SCRATCH=1 node scripts/test-native-local-source-result.mjs \
  /absolute/native-artifact-directory FULL_SOURCE_SHA \
  /absolute/installed-duckdb-node-api-package \
  /absolute/sqlite-library /absolute/crypto-library /absolute/duckdb-library
```

Use the existing local verification guard and agreed allocation around this
command. Each CLI command retains its 15-second timeout. The harness does not
obtain a Heavy allocation or rebuild a missing/stale executable automatically.
This Source/Result selection is separate from the older adoption/ingress cases.

The fixture loader only seeds the database. Every operation executes in the
selected Native executable with an empty PATH. The producer exits, and its start
reply is discarded before another process looks up the original Submission.
The recovered Run reference comes from lookup, not the discarded reply. The
original database is then unavailable at its configured path, and the Program
file is removed. Both explicit reads use the stored Result.

The harness checks metadata-only lookup, unchanged Run control revision, one use
per read grant, no reopening of an existing attempt, an explicitly new read,
original columns/schema, a one-byte prefix without a completion receipt, a
foreign Run reference, and replacement of an adopted read original. Journal
inspection is read-only diagnostics; it neither repairs records nor substitutes
for the public commands. All process outputs, artifact/input digests and original
Host/Store custody remain in the owned scratch directory for review.

Successful exit does not prove npm installation, Effect approval, cleanup-fault
retry, all temporary holders released, or physical Source/Compute call counts.
Those need their corresponding public Owner observations and acceptance. The
`sourceAcquisitions` and reread count expectations remain in the independent
fixture and must not be reported as measured by this harness.
