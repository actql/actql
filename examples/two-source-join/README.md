# Join two DuckDB sources

This executable example submits one ordinary JSON Program through `@actql/node`.
The Host reads two independently bound DuckDB databases, joins their captured
rows, and publishes the Named Result `joined`. The Client only submits and reads
the Result. It does not fetch the inputs or implement the JOIN.

## Run the example

Prepare and install the five development tarballs in a fresh directory outside
the checkout using the [Quickstart](../../README.md#quickstart).
Before leaving the checkout, set `ACTQL_CHECKOUT` to its absolute path. From the
consumer directory, copy this example:

```bash
cp -R "$ACTQL_CHECKOUT/examples/two-source-join" two-source-example
cp "$ACTQL_CHECKOUT"/adapters/host-node/fixtures/two-source/*.json two-source-example/
```

Then run these commands in that consumer directory:

```bash
node two-source-example/setup-example.mjs
node two-source-example/run-example.mjs
cat joined.jsonl
```

The setup creates two small local databases from
[`database-rows.json`](../../adapters/host-node/fixtures/two-source/database-rows.json), with separate source references,
physical paths and read grants. It does not download data or need credentials.
Run setup once in a fresh directory; it will not replace an existing table.
The installed `@duckdb/node-api` dependency is used only for this setup.

Expected rows, including both duplicate occurrences, are:

```jsonl
{"id":1,"left_amount":null,"right_amount":100}
{"id":3,"left_amount":30,"right_amount":300}
{"id":3,"left_amount":30,"right_amount":300}
{"id":3,"left_amount":30,"right_amount":301}
{"id":3,"left_amount":30,"right_amount":301}
```

`joined.schema.json` contains the actual Result description: `id` is a
non-nullable number; `left_amount` and `right_amount` are nullable numbers, in
that column order. The independently authored
[`two-source-join.expected.json`](../../adapters/host-node/fixtures/two-source/two-source-join.expected.json) specifies both
rows and column contracts. [`two-source-join.program.json`](../../adapters/host-node/fixtures/two-source/two-source-join.program.json)
owns the JOIN and its output ordering.

`joined.run.json` retains the Run reference. Running only `run-example.mjs` again
uses the same request ID and Program and reads the same Run. Both scripts close
their normal Client or database owner in `finally`; keep `two-source-example-data`
while its Run and Results are needed. All generated databases, state and output
files belong to this example's consumer directory, which can be removed once
those Results are no longer needed.

## Supported boundary

This example uses the installed bounded two-source, effect-free JSON Program
profile. Each source has its own acquisition stage; their retained Results feed
the local JOIN stage. Both acquisitions must select the Native query route.
The profiles explicitly declare `acquisitionPlanning`; priority prefers the
eligible Native candidate without inventing cost estimates. Current read grants
and finite Host limits still apply. Broad acquisition for two sources is not
supported by this profile.

This is not SQL/Pipe two-source or INFER composition, and does not provide a
live Salesforce or warehouse integration. It reuses the capability described in
[the two-source Host boundary](../../docs/reviews/2026-10-02-two-source-public-host.md).
The existing packed acceptance executes these exact files through both Embedded
Local and HTTPS using one shared tarball set; it also verifies Result schema,
stream completion and request reuse. HTTPS accepts an explicit connection file
as the optional argument to `run-example.mjs`; no replacement executor is used.
