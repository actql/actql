# First M1 installed process preparation

`first-m1-public-process.mjs` is an acceptance application, not a new runtime
Owner, provider installer, numerical profile or live-call authorization. Copy
it into an ordinary consumer with the selected `@actql/node`, Local runtime and
optional Provider packages installed. It imports only `@actql/node`; there is
no checkout runtime fallback, fixture Provider or direct SQLite/Store access.

Before a real execution, the original trusted installation must have its
complete adopted same-Ledger supplier and original policies. Real Provider
use, credentials and billing also require the existing separate approval. The
commands below do not grant any of these. They have not passed against a real
Provider merely because the process-flow unit tests passed.

The application module exports a default object with:

- `installation`: the actual existing Node Host installation. Its registration
  uses the installed optional Provider facade and actual original materials;
  do not substitute the historical first-M1 fixture policy, hashes or byte
  amounts. The existing original startup and currentness admission still run.
- `program`: the selected one-row/one-Slot Program with its original contracts.
- `resultName` and `expectedRows`: the independent Named Result expectation
  (exactly one row for this selected scenario).
- `signer`: the actual authorized Checkpoint reviewer for the explicit `run`
  phase. No reviewer/key is generated or inferred here.

Do not log secrets from the application module. Its source-file digest in the
evidence is a selection-change check only: it authenticates neither imported
dependencies, runtime layout, authority nor original Store custody. Retain the
actual installed artifact/lock manifests and original physical witnesses too.

For the already selected pinned Node process, invoke the normal public preload
before the entry. Use the separately reviewed eager recipe when required by
the selected startup coverage; this script does not choose between recipes.

```sh
node --require @actql/node/selected-infer-startup ./first-m1-public-process.mjs \
  run ./application.mjs ./new-state ./new-evidence 30000
node --require @actql/node/selected-infer-startup ./first-m1-public-process.mjs \
  read ./application.mjs ./new-state ./new-evidence 30000
```

The final argument is an explicit application verification deadline in
milliseconds, not a Model fuel/duration/byte limit or a permission to extend
the actual Provider operation. The enclosing bounded verification supervisor
must still preserve original Unknown/cleanup duties on timeout.

`run` refuses an existing state or evidence directory before importing the
application or opening a Host. It retains the original public submission ref
before the single submit, then retains the Run ref. It discovers and reads the
actual Model Checkpoint, records the approval attempt before the one public
resolution call, waits on the same original live Run, and checks its Named
Result. Approval is never inferred from a saved CID or application Bool. This
phase does not close/reopen the Model between preparation and approval, so
cold Model adoption is not introduced as a new first-start prerequisite.

`read` requires the original selection and state, attaches the saved Run ref,
checks terminal success and reads the same Named Result. It never calls start,
resolve, reconcile or a private Model restore API. Result read may perform its
ordinary authenticated Store I/O; no claim of zero I/O is made.

Failures retain the original files. There is no automatic submit, resolution or
cleanup retry and no deletion/reset. A lost submit/approval response must use
the existing public lookup/reconciliation procedure, not a new `run` against a
different state directory. A primary failure and a failed Client close are
reported separately, without raw error messages or answer/credential bodies.

Output `physicalDispatches: null` and `physicalCleanup:
'not_independently_measured'` are deliberate. The real acceptance still needs
the original physical witness for approval-before0/after1, saved raw/Entry/
Store/Journal identity, fresh-process additional dispatch0, and cleanup.
Neither matching rows nor a completed `client.close()` creates that evidence.
`normalProfile: null` means this script supplies no profile-adoption evidence.
It is not a replacement numerical policy.

`scripts/first-m1-public-process.test.mjs` exercises separate processes with an
explicit public Client double. Those cases establish only the application's
call order, original-ref retention, failure handling and no automatic resend.
They are not SDK/Core/Store/LLM or pristine installed-product E2E evidence.
