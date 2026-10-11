# Native holder Catalog and Review custody

## Scope

This dependent change connects the existing holder completion/progress driver
to Catalog-backed original Review preparation. Its parent is #1462; the final
destination is main after #1460 and #1462 are integrated. It changes private
holder references and callback signatures only. No public wire, CID, grant,
Owner, scheduler, Ledger or persisted record format is added.

The driver retains one installed credential service, captured input context,
Catalog Store custody and first read/save failure on the same checked consumer
task. Original producer journal/Invocation, exact dispatch, runtime and Site
generation are checked independently. The existing capture Owner's consumer
binding projection must match installed policy before Provider read.

The first eligible call uses the existing credential and named Catalog read/save
Owners. Later calls can retry only the retained Store custody, with its original
holding and response. They cannot enter Provider read again. Confirmed metadata
is passed to the original checked Mapping/Review preparation entry introduced in
#1462. The resulting Review owns its input context; rejection returns the same
pending cleanup handle. No Source or Compute execution is repeated.

## Cleanup and unresolved boundaries

Review cleanup precedes Catalog cleanup and credential-service handle closure.
Each failing handle remains referenced until its own Owner confirms cleanup.
Store cleanup may return `Ok(false)` when an earlier release was already
confirmed; that is not a reason to repeat Provider work. A service close failure
after Store cleanup does not lose the cleanup confirmation or resurrect reads.
These local closes do not issue formal dispatch cleanup or Released evidence.

A failure before Store custody exists retains the original response or typed
read issue. The driver refuses another physical read. If the failure contains
an original response without Store custody, local cleanup stays pending rather
than discarding that evidence and claiming release. A subsequent change must
connect recovery/retirement of that exact response through the existing
credential and Store Owners; this change does not invent terminal evidence.

The production CLI still has no installed Review configuration/publication
callback. The installation constructor is therefore intentionally unused by
that entry. Registering the independently configured CLI installation, durable
restoration and actual Provider/Cloud acceptance remain separate work. Neither
these references nor matching Native compilation prove public Effect execution.

## Verification boundary

Select `moon check --target native src/cmd/native_remote_resident_site` under the
existing bounded non-Heavy guard. This compiles the holder and its existing
white-box callers; it executes no Native test, Provider request, Store I/O,
approval, public Result or release. Formatting and `git diff --check` are light
checks. Fixed-source receipts and the actual commands are recorded separately
in the working evidence and PR body. Hosted CI remains stopped.
