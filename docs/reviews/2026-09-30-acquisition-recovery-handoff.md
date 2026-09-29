# Acquisition end handoff for the installed Host

## Boundary

An installed Source can fail after provider I/O without returning a capture.
The Source adapter states whether the attempt was not started, stopped, or
still unknown. An unknown attempt may have an owner whose `close`, `cleanup`,
and `cleanupPending` operations retain the remaining physical responsibility.

The Host now passes `reportAcquisitionFailure` to `sourceProfile.open`. The
adapter reports its `AcquisitionOpenError` before a later boundary can wrap the
exception. The standard dispatch owner and acquired Effect computation each
keep the reported end separately from the thrown error. A direct, unwrapped
`AcquisitionOpenError` remains supported; no report and an ordinary exception
remain unknown. A reported owner is used only for cleanup, never to retry the
Source, Compute, or Effect dispatch.

The installed DuckDB Source forwards this receiver to its physical opening
adapter. An invalid preparation reports `not_started` before native I/O. The
existing Salesforce Source still returns its own direct acquisition error;
this change does not alter its provider logic or the Outbound implementation.

## Evidence and remaining work

The dispatch and acquired Effect tests wrap a reported failure in an ordinary
error. They check that the exact recovery owner survives, cleanup remains
pending until that owner confirms release, and no Source or Compute starts
again. A separate case preserves a confirmed no-start observation through the
wrapper. The DuckDB Bridge test checks that its real opening adapter reports
an exact preparation refusal. Invalid or conflicting reports are rejected.

This closes the H2 acquisition error-wrapping gap identified in the
H1–H3 remaining-work audit. H1's installed Run-control projection error and
H3's remaining installed ABI adapters and publication role/action checks are
separate follow-ups. The journal initialization cleanup is in PR #71.
