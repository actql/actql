# Original Native Review to Cloud current claim

## Connection

The original retained Review confirms its paired Checkpoint report and durable
typed ACK, then admits the delivery with independently installed Host
authentication and Reviewer authorities. Only that admitted delivery supplies
expected original dispatch, report, Checkpoint, Resolution, intent and claim.

`cloud_resume_observer` installs a read closure using the operator-configured
Cloud TLS/Site-credential HTTP client and fixed current-read URL. Each invocation
uses a fresh caller-owned challenge, checks physical Site/Review continuity
before and after HTTP, and admits a bounded exact response against those
original expectations. The configured caller provides fresh challenge IDs and
its own clock; the immediately previous challenge cannot be reused. No unbounded
challenge inventory is retained. The returned lease/view and local clock feed
the existing common Resume fence. The server's `observedAt` is diagnostic
framing only and never supplies the local clock.

The framing decoder is private. There is no public arbitrary-response-wire to
execution-observation API. Transport failure, missing evidence, expiry,
settlement-only mode or a substituted original identity returns unavailable
without renewing the claim, sending a Provider write or completing cleanup.

`execute_remote_approved_row_with_cloud_current` supplies this independent read
to the existing row preparation/execution Owner. Host/Reviewer validation,
Provider access, Original request binding, Ledger, saved-response settlement,
unknown custody and pre-send fencing remain there. This adapter creates no
scheduler, approval, ledger or alternate execution semantics.

## Evidence and remaining boundaries

The selected JS white-box cases isolate private request/response framing,
original identity mismatch, stale challenge, lease expiry, local time, exact
fields/duplicates and bounded admission. Authored codec fixtures are not proof
of an original Review, ACK, trusted HTTP read, physical Effect or Provider
permission. Matching Native compilation checks the actual Review/HTTP/common
Owner types and additive public declarations.

Physical Native HTTP acceptance and installation in the production holder are
still pending. The configured Cloud route is supplied by Cloud #266, dependent
on #265 and #264. No formal Cloud OSS cohort adoption or Native binary replacement
is performed here; Cloud's existing `ae4f29be105e649c621ece7ed3b1584732625639`
cohort is not relabeled as this source.

Actual approval/restart, Provider write, saved response/unknown reconciliation,
Result publication, release and Preview acceptance remain required for Cloud
#138. Historical #88 Runs and previous physical failures remain separate.
This change targets OSS main and does not authorize Hosted CI, Heavy execution,
public mutation or deployment.
