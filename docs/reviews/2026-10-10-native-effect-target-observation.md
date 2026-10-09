# Native Effect target observation

## Implemented boundary

`observe_native_salesforce_effect_target` connects an existing checked
Salesforce single-update request to real Native HTTPS through the installed
credential resource Owner. It requires a separate
`salesforce:record:observe` grant, the trusted installation's credential org,
matching Catalog/Site/Run scope, a current compatible Catalog, valid finite
limits, and the exact installed target path before physical acquisition.
It does not widen the installation's fixed-path allowlist.

The real response is admitted by the existing Salesforce target observation
Owner, which checks the record identity and typed mapped fields. The existing
Provider Owner issues the target guard and before/after row. These are inputs
to whole-Preview admission, not approval or permission to apply an Effect.
The configured credential org must come from trusted Site installation state,
not a Program or an untrusted request.

The common Native credential connection now rereads durable grant revocation
and the trusted clock after the authorization callback. It supplies those
current facts to the existing credential-use Owner before HTTP. A grant
revoked during claim is recorded as failed and sends nothing. The existing
unqualified credential API uses the same path and remains available.

This is a successor to #1178's actual retained-input proposal projection.
The target-read connection is not yet installed in the resident holder's
whole-Preview capture path. No new execution, authorization, Ledger,
scheduler or cleanup semantics are introduced.

## Fixed-source local evidence

Implementation commit: `0933fea7231bbdaf0061e9ed1507b50c18d97b4a`.
Exact clean verification source, including its actual package registration
history declaration: `a0d5e8bd7e8418592b4d5996ecd5c20f3ff6b161`.
The source receipt is authoritative if this abbreviated handoff is updated.

The focused physical runner is:

```sh
ACTQL_TEST_SCRATCH_ROOT=<owned-evidence-directory> \
  node scripts/test-native-salesforce-effect-preview.mjs
```

Run it through the existing local verification lock and bounded wrapper.
It uses pinned MoonBit, a local HTTPS server with a generated test CA, real
libcurl, real SQLite and OpenSSL signature verification. It calls the existing
nonzero-test runner on
`src/platform_native/salesforce_effect_preview/target_native_wbtest.mbt`.
It is also registered in the existing `check:native-http-client` command;
no new workflow or duplicate Hosted CI run is added.

Clean-source evidence: `_build/native-effect-target-1791568820638/`.
Native tests: **6 passed, 0 failed**. Native interface generation, formatting
and `git diff --check` passed. The physical server accepted exactly three GETs
across the six cases and zero writes:

- The normal target observation preserved decomposed Unicode and CR/LF in the
  typed before value, issued the exact target guard, and proposed the independent
  new value. Reusing the same grant use caused no additional HTTP and did not
  rewrite its succeeded observation.
- Wrong generation, credential org, read operation, limits and installed path
  were rejected before authorization/consumption/I/O. The originally unused
  grant still admitted its one subsequent correct physical read.
- Current authorization denied at send recorded failure and read nothing.
- A real foreign-record HTTP response produced no target guard; retrying its
  consumed use did not acquire it again.
- Grant revocation during claim sent nothing through both the new target-read
  entry and the pre-existing Native credential API.

The receipt and exact Native whitebox executable digest are preserved in
`physical-receipt.json` below the evidence scratch directory and `artifact.json`
at its root. This executable is not a formal production resident binary.

## Counterexample and preserved failures

`_build/native-effect-target-1791568665521/` preserves the actual pre-fix
revocation failure: **4 passed, 1 failed**, with a fourth GET after revocation.
The failing case was the real Native credential call, not an extracted function
or a mocked successful Provider reply.

`_build/native-effect-target-1791568649759/` preserves an earlier diagnostic
compile failure from an incorrect nested error pattern in the added test.
It is not counted as executed product acceptance. Earlier 4/4 and 5/5 results
are diagnostics, distinct from the clean-source 6/6 result.

## Unfinished acceptance

The caller still must construct checked requests from the actual retained
proposals, install trusted credential/Catalog facts, admit and verify the
complete Preview, persist the Checkpoint and commit the original Cloud Run to
waiting. Physical Host restart recovery, current approval, Effect apply and
unknown-outcome reconciliation, final Effect publication and formal release
are not proved by this target-read acceptance.

Source and consumer execution are not repeated here. Their actual Native
capture evidence remains in the parent PR series. No external Salesforce org,
Cloud Preview, deployment, new formal OSS cohort or #88 historic Run is changed.
Hosted CI remains stopped. Main adoption must follow the pending parent series;
this branch does not establish a main-integrated Cloud Effect configuration.
