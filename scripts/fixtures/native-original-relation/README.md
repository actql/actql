# Native original relation runtime inputs

This is setup data for a private matching-target diagnostic, not a CLI install,
normal product profile, Source grant, or successful-query oracle. The Common
input emitter uses the current Row declaration constructor. Expected query rows
remain independently authored in the Native test.

1. Select a new absolute input directory and create it with mode `0700`.
2. With the repository's pinned Moon toolchain in `PATH`, run:

   ```sh
   ACTQL_TEST_NATIVE_RELATION_ENVIRONMENT_OUTPUT="$INPUT/environment.json" \
     node scripts/local-checks.mjs test moon --timeout-seconds 300 -- \
       --target js -j 2 src/native_relation_fixture_inputs
   ```

   The optional output is an exclusive `0600` write. Without the variable the
   focused test validates input construction without writing files. Never
   reuse an existing output or extract canonical bytes from diagnostic logs.

3. Select an existing supported-platform runtime recipe and its actual SQLite/Crypto
   producer receipts, plus the original producer checkout. The component
   receipts must match the recipe's original source, target, and library bytes.
   Every recorded compiled input is re-observed. Checkout-owned compiled inputs
   must also match the current checkout; no source SHA is relabeled.

   ```sh
   node scripts/native-original-relation-runtime-fixture.mjs \
     "$FRESH_FIXTURE_DIRECTORY" "$RUNTIME_RECIPE" \
     "$SQLITE_PRODUCER_RECEIPT" "$CRYPTO_PRODUCER_RECEIPT" \
     "$ORIGINAL_PRODUCER_CHECKOUT" "$INPUT/environment.json"
   ```

The helper creates a new `0700` namespace and exclusively writes private inputs.
It preserves all original library, license, Common contract, source, and ABI
identities through the existing runtime producer and validator, replacing only
the environment asset with the freshly generated input. It records exact
metadata and provenance in `preparation-receipt.json`. It never initializes a
Host/Store, creates a Source grant, changes budgets, builds or runs a Native
executable, uses a Node query fallback, or resets an existing namespace.

4. Complete the untouched configuration by selecting the emitted setup array:

   ```sh
   ACTQL_TEST_NATIVE_RELATION_CONFIGURATION_INPUTS="$FRESH_FIXTURE_DIRECTORY/configuration-inputs.json" \
     node scripts/local-checks.mjs test moon --timeout-seconds 300 -- \
       --target js -j 2 src/native_relation_fixture_inputs
   ```

   Common constructs only `run.json` from the original recipe's source-free
   environment and unchanged Compute assets, at the authored fixture time
   `2026-11-06T00:00:00.000Z`. The test confirms that the product assembler still
   rejects a nonempty Source environment. This run packet is compatible input
   for generic adoption, not a Source result-publication grant.

5. Before any Native adoption, prepare the three Account-refusal cases:

   ```sh
   node scripts/native-original-relation-runtime-fixture.mjs \
     --prepare-refusals "$FRESH_FIXTURE_DIRECTORY"
   ```

   These exclusive `0700` sibling namespaces copy the immutable configuration
   and source bytes exactly, changing only the Source Account entry: omitted,
   wrong connection, or wrong resource. The Run grants are unchanged. Existing
   or initialized namespaces are never reset or copied.

The outputs are `runtime/` and `test-input/` containing `environment.json`,
`row-declaration.json`, `records.json` (62 bytes), `account.json`, `runtime.json`,
and the Common-emitted `run.json`. The Account has only the authored
`operator`/`machine-user` Run-control (`cli`, `run`, read/submit/cancel) and
independent Source-read (`native-file-fixture`, `records`, read) entries.
The selected Native diagnostic's external fixture owner separately prepares
its finite backing extent before Moon opens these originals. The positive test
observes those original files and closes its own physical owners. A failure leaves the newly attempted namespace intact for
inspection; select a new directory for a later attempt.

Before Native execution, validate the actual serialized inputs through Common:

```sh
ACTQL_TEST_NATIVE_RELATION_AUDIT_ROOT="$FRESH_FIXTURE_DIRECTORY/test-input" \
  node scripts/local-checks.mjs test moon --timeout-seconds 300 -- \
    --target js src/native_relation_fixture_inputs
```

The three cases include real environment, runtime-descriptor, Row document,
Compute contract, Result Policy and retention-policy admission. Without the
audit root, that case validates generated setup data only. Neither mode proves
Native custody, private Runtime binding, signing or Journal execution. The
Account helper is separately pinned to an independently authored Common
admission regression: entry IDs and operation selectors must be in canonical
ascending order without changing their permission sets.

Focused helper/data checks:

```sh
node scripts/local-checks.mjs test node -- \
  scripts/native-original-relation-runtime-fixture.test.mjs \
  scripts/native-cli-local-runtime.test.mjs
```

## Strict Native Core selection

The existing full `scripts/test-native-core.mjs` selection provisions the exact
`src/platform_native/relation_file_work_tests/relation_file_original_physical_scoped_test.mbt`
case in `scoped-review-values`. Other files in that package and existing Local
profiles are unchanged. The compiler must discover and execute its original
case; missing inputs or zero execution are failures.

`native-core-relation-work-fixture.mjs` uses the existing current-clean-HEAD
Core component producer and its hashed original receipts. It supports the
producer's Darwin arm64 and Linux x64 targets, verifies original compiled
provenance, and uses the current Common emitter to construct the Source
environment and baseline run assets in a separate JS target. It then invokes
the same runtime producer and validator above. No retained workspace path or
older source identity is a CI input.

Each selected case gets a new private input namespace and an exclusive `0600`
`backing` file with the authored 768 MiB sparse extent. The Native test receives
the exact root, runtime root, source SHA, platform and manifest digest through
`ACTQL_TEST_RELATION_*`, with mode `positive`. The helper also accepts the three
Account-refusal modes when an explicitly selected diagnostic requests them.
Ambient full-campaign relation roots cannot activate a different case.

This preparation is setup data only. It neither proves Native execution nor
grants Source result-publication authority. A focused raw Moon invocation must
receive its separately prepared inputs; it cannot silently skip the case.
