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

The response is a closed JSON object with exactly these fields:

| Field | Type | Meaning |
| --- | --- | --- |
| `version` | string | `actql-placement-policy/0.1` |
| `request_id`, `run_identity`, `authority`, `candidate_set_cid` | string | Exact echoes of the pending request |
| `generation`, `revision` | nonnegative safe integer | Exact echoes of the pending request |
| `deadline_ms` | decimal string | Exact echo of the pending request |
| `position` | nonnegative safe integer | Original feasible assignment position |
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
