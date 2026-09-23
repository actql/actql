# Placement policy wire contract 0.1

The external policy ranks a bounded set of already admissible assignments. It
cannot create a task, capability, budget, grant or execution authority. The
common planner remains the source of truth for feasibility and dispatch.

The Host obtains a `PolicyRequest` and its immutable candidate projection from
the same pending choice set. `placement_policy_request_json` emits a bounded
closed JSON request containing version, request ID, Run identity, Coordinator
authority, candidate-set CID, generation, revision and deadline. The candidate
projection is sent separately as the exact canonical JSON returned by
`strategy_policy_candidates`; its CID must equal the request's
`candidate_set_cid`. The Host must not send rows or arbitrary local handles.
Candidate metadata can still be sensitive and requires an explicit disclosure
policy at the Host boundary.

The portable DuckDB/Local standard Host exposes this boundary through
`prepare_dispatch_policy_choice`, `dispatch_policy_candidates`,
`prepare_dispatch_policy_request` and `commit_dispatch_policy_response_json`.
Its ordinary `prepare_next_dispatch` cannot start a task while the external
choice is pending. This keeps the product Host on the same common admission
path as an internal policy decision; the environment still owns HTTPS,
authenticated endpoint mapping, disclosure and the fresh clock observation.

The native standard Host adapter prepares one consultation from that exact
pending choice. Its configured HTTPS endpoint is verified by the maintained
mTLS client, and the configured policy ID is passed to common admission rather
than accepted from the response. A required Host disclosure callback sees the
exact request and candidate projection before any network call. The adapter
uses a durable monotonic clock before sending and after receiving, bounds the
request and response, and retains the same pending consultation after a
transport failure. A retry sends the same request ID and candidate CID; it
does not dispatch or silently select the offline policy. The caller must
retain the consultation owner until it commits or explicitly ends the Run.
An environment without native HTTPS uses the same portable standard Host
contract with its own physical adapter.

For the supported native Host profile, the application supplies a pinned HTTPS
endpoint, its expected `policy_id`, a CA bundle, a client certificate and key,
and a durable SQLite-backed `NativeTrustedClock` scoped to the Coordinator
authority. It creates the native HTTP client with an explicit response-byte
limit and connection/operation timeouts. The response limit must cover the
closed policy response while remaining bounded independently of the request
limit (`max_envelope_bytes`, at most 16 MiB). The application also supplies a
disclosure callback that decides whether this exact request and candidate
projection may leave the Host. These are trusted deployment settings, not
fields accepted from the policy response or the ActQL Program. The policy
endpoint must present a certificate valid under the configured CA and the
client certificate identifies the caller; no plaintext or unauthenticated
fallback is part of this profile.

The Host calls `prepare_native_standard_policy_consultation` once for the
pending choice, retains the returned owner, and calls
`consult_native_standard_policy` before `prepare_next_dispatch`. A transport
error leaves that owner pending; retrying it sends the same request and
candidate CID. An application that abandons the consultation must explicitly
end the Run. It must not create a fresh request merely because a response was
lost, nor interpret policy failure as permission to retry an already started
task.

The response is a closed JSON object with exactly these fields:

| Field | Type | Meaning |
| --- | --- | --- |
| `version` | string | `actql-placement-policy/0.1` |
| `request_id`, `run_identity`, `authority`, `candidate_set_cid` | string | Exact echoes of the pending request |
| `generation`, `revision` | nonnegative safe integer | Exact echoes of the pending request |
| `deadline_ms` | decimal string | Exact echo of the pending request |
| `position` | nonnegative safe integer | Exact position in the projected feasible candidate set |
| `policy_id` | string | Must match the authenticated policy peer identity |
| `policy_revision`, `explanation` | string | Bounded decision provenance |

`admit_placement_policy_response_json` rejects unknown fields, missing fields,
oversize input, malformed values, altered request fields and a policy identity
that differs from the Host-authenticated peer. A Host must authenticate its
policy endpoint using its deployment's maintained transport/identity mechanism;
the `authenticated_policy_id` argument is the result of that authentication,
not an assertion read from JSON. The Host must retain the exact pending request
through the I/O interval and submit the decoded decision through
`commit_compute_host_policy_response_json`. That common commit rejects expiry,
replay, changed Run generation or resource snapshot, unavailable registrations
and positions outside the feasible set. A rejected response is not a reason to
restart a task or silently choose another candidate.

The Host may explicitly choose the offline policy before dispatch when remote
consultation is unavailable. That decision is recorded as `OfflineLatency`.
After dispatch begins, policy communication failure is not an execution retry
signal. Host-specific networking, credential storage and the private ranking
algorithm are outside this contract.

This contract does not sign every packet or prescribe a custom transport. A
durable policy audit record, if required by a deployment, needs an independently
authenticated journal entry bound to the request and decision. The current
common API records policy ID/revision/request ID and explanation, but does not
itself provide a cryptographic audit signature.
