# Client transport outcomes and response budgets

## Completion unit

This unit addresses review items 1 and 2: submit outcome consistency between
HTTP and installed in-process ingress, and operation-specific response wire
budgets. Authorization decision lifetime, telemetry, and Effect commit
Checkpoint installation remain separate work. No public wire shape, CID,
stored record, authorization policy, or 0.1 contract version changes.

The base is `5c2cebdaa7931a8680b43fc0fb4a4324151f77f8` (main including PR #21).
Verified implementation SHA: `c5628828a19e1eeaec1ed33fa9c982048cc389b6`.
This record is a documentation-only follow-up to that implementation.

## Baseline findings

Both review items remain reproducible at the base, not merely inferred from
the older review SHA:

- The base SDK returns `ClientHostFailure` without a generated request ID
  for an in-process internal `ClientError` after submission.
- Running the new ingress comparison against base modules accepts a legal
  held response over HTTP but rejects it through installed in-process ingress.
- A 1,048,576-byte Review body encodes to 1,398,104 base64 bytes. The base SDK
  rejects it with `ReviewReadUnknown` / `HostControlResponseLimit` even though
  the body fits the requested limit.

The baseline probes used the actual SDK and ingress source from the fixed
base. Dependency imports were resolved to local files for isolated loading.
The Review probe used a bounded synthetic HTTP response, not a remote service.

## Implementation and evidence

- `performClientSubmit` owns the shared prepare/invoke/reply-validation order.
  Both installed ingress adapters use `validSubmitReply`, including its exact
  request binding for held replies. The wrapper never retries the handler.
- The SDK recognizes explicit request, preparation, policy and admission
  refusal contracts independently of exception classes. Unknown internal
  codes, malformed acceptance, and transport failures retain the original
  request ID and lookup context as `SubmissionUnknown`. A generic public-code
  pattern or arbitrary HTTP 4xx status does not prove refusal.
- The existing installed-Host test confirms missing account configuration is
  a known refusal: no dispatch and no accepted request. That refusal remains
  distinct from uncertain admission; unavailable decisions are not policy deny.
- Review wire budget is `4 * ceil(bodyBytes / 3) + 1024`. Resource inspection
  and peek budget JSON-text escaping at at most six wire bytes per payload
  byte, plus bounded names and envelope metadata. Decoded body checks remain
  independent. Other control responses and error bodies retain their 1 MiB
  bound. Counted stream bytes enforce the limit regardless of Content-Length.
- The HTTP/in-process matrix uses the same handlers for successful admission,
  held requests, preparation and start refusal, post-acceptance exceptions,
  malformed replies, and foreign held replies, with explicit and generated
  request IDs. It checks acceptance counts and exact lookup context.
- SDK tests cover maximum Review and peek bodies, one-byte overflow, base64,
  quote/backslash/multibyte escaping, and cancellation of a stream exceeding
  its operation budget despite a smaller declared length.

## Validation

At the implementation SHA above:

- `node scripts/local-checks.mjs run client`: passed. Distribution Client
  tests: 176/176; Salesforce Site tests: 192/192. Packed Node/browser,
  packed Checkpoint, and native Client mTLS checks also passed.
- `node scripts/local-checks.mjs run host`: passed, including retained and
  publication ownership, process capacity, remote admission, Checkpoint
  journal, native retained files, portable runtime packages, and packed Local
  Values/acquired-input execution.
- Targeted ingress, SDK and wire tests: 62/62 before the broader jobs.
- An initial local run lacked the pinned DuckDB Node dependency. It was
  installed from its lockfile before rerunning. The broader Client regression
  then caught an omitted missing-account refusal classification; the corrected
  implementation passed both jobs above.

These are local tests, including simulated provider faults and real local
HTTP/SQLite/runtime paths. They do not establish live Salesforce coverage.
Linux CI on the final PR SHA is separate and must be checked in the PR.
Generated runtime bundles remain ignored and are not committed.
