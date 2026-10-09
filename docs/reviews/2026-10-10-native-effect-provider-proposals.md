# Retained Native Effect proposals to Provider observation

## Implemented boundary

`observe_native_resident_effect_targets` reads the retained consumer's actual
Effect proposals, checks the original Run definition and Effect member against
the checked Catalog mapping, and constructs bounded single-update requests
through the existing Catalog Owner. It preserves data strings through the
existing value JSON parser; configuration normalization is not used for values.

The caller supplies trusted installed credential access for each checked
request. The existing Native credential and Provider Owners check current
authorization and Catalog scope, perform the physical HTTPS target read, and
issue the target observation and before/after Preview row. The complete array
is returned only after successful checked export. A failed observation retains
input custody and the original credential-use outcome; it does not retry Source,
Compute or the Provider read automatically.

This additive Native API supports the checked update-by-record-id mapping. It
does not issue a whole Preview, approval, Checkpoint or write permission. It
introduces no scheduler, Ledger, wire format or stored-data migration.

## Fixed-source local evidence

Exact clean verification source:
`809d8878e4d885432bd88df9df6c273311e7396f`.

The focused physical runner is:

```sh
ACTQL_TEST_SCRATCH_ROOT=<owned-evidence-directory> \
ACTQL_TEST_DUCKDB_LIBRARY=<compatible-native-library> \
  node scripts/test-native-salesforce-effect-preview.mjs --resident-proposals
```

Use the existing verification lock and bounded wrapper, pinned MoonBit, and
matching Native SQLite, libcurl and OpenSSL libraries. The runner creates its
own signed test bundle and generated HTTPS test CA. That test bundle is not a
production Site binary or deployed authority.

Evidence is retained at `_build/native-effect-provider-1791571427562/`:

- Formatting, affected Native interface generation and Native type checking
  passed, including the consuming whitebox tests.
- The real Native retained-consumer file passed **11 tests, 0 failures** through
  the existing nonzero-test runner. Existing Source/Transfer/consumer cases were
  retained; two new cases exercise physical Provider observation and current
  authorization denial.
- Source acquisition, producer execution and consumer execution each occurred
  once. The consumer used the committed receiving holding and its existing
  borrow/capture/cleanup Owners.
- The independent Result was `[{"id":3,"record":"001000000000001"}]`, with a
  non-nullable number and a non-nullable string bounded at 15 UTF-8 bytes.
- The independent HTTPS target contained `Count__c: 7`; the proposal contained
  `Count__c: 3`. The checked Provider row preserved those distinct before/after
  values and the original successful credential-use record.
- The physical receipt records **one Provider read and zero writes**. Invalid
  limits and a foreign Effect member were rejected before access acquisition;
  denied current authority sent no Provider request. Existing input cleanup
  and reservation checks passed without early or duplicate pin return.
- `git diff --check` passed.

`source.json`, `receipt.json`, `artifact.json` and the scratch
`physical-receipt.json` preserve the source, commands and actual results. The
compiled Native whitebox executable has SHA-256
`3a37987e1898cae99fe66c4de18f31a416c3a172d90aac80a8c7741e60a3d2df`.
It is not a formal distributed resident binary.

The normal Native HTTP runner also registers these cases. Its full suite was
not run locally; focused execution does not establish full-suite acceptance.

## Preserved failures

Earlier evidence directories remain available and are not rewritten as passes:

- `native-effect-provider-1791570165580` and
  `native-effect-provider-1791570358400`: fixture admission aborted before
  Provider I/O. The generated Environment sections needed canonical CID order.
- `native-effect-provider-1791570603781`: 9/11; the new independent schema
  assertion omitted the checked ASCII literal's 15-byte bound.
- `native-effect-provider-1791570920126`: clean source
  `603bbee008f11399f2f34bb9956f702a211129ff`, 9/11. Physical target observation
  succeeded, but the fixture incorrectly expected its producer pin to have
  already been returned. The fixture now returns its own pin once and verifies
  that the duplicate return does nothing.

Earlier compilation diagnostics and the intermediate clean 11/11 result at
`72755f71482360b36a763f70af7e26a0fab0fdf9` are distinct from the final-source
receipt above.

## Remaining connection

The real target observations must next be bound to the original invocation's
whole Preview and capture, persisted through the Checkpoint Owner, and connected
to the original Cloud Run's waiting/approval/resume path. Approval, physical
Effect apply, unknown-outcome reconciliation, Host restart, Cloud publication
and formal task release remain unverified by this unit. Native input cleanup
success is not a Cloud Released observation.

No external Salesforce org, Cloud deployment, formal OSS cohort or historical
#88 Run was changed. Hosted CI remains stopped. The Native parent series must
reach main before formal Cloud package/binary adoption; a successful component
fixture is not completion of Cloud Effect acceptance.
