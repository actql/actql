# Remote retained task inputs

A dependent task receives the output of its checked producer edge, not any
material with equal bytes or schema. `prepare_client_retained_input_edge`
joins the original admitted Run to the checked producer fragment/output port
and consumer fragment/input port. The fragment identities retain the checked
schema and ordered computation. Resolving this edge issues no start claim.

`prepare_client_retained_input_producer` then joins that edge to the exact
producer dispatch, attempt, registered managed output subject and durable
execution evidence. The dispatch must name the original Run and producer
fragment. Its retained material, holding and evidence must agree with the
current dispatch record. A released, unavailable or cleanup-releasing producer
cannot authorize a new handoff. A previously issued reference is rechecked
before use; historical completion alone is insufficient.

## Independent destination custody

The portable Run publication owner joins the producer reference to an existing committed
Transfer and its exact destination receipt. It checks source occurrence,
manifest, schema, logical view, representation codec, row count and byte
count. In the initial single-Site profile, both Transfer endpoints must match
the current Site identity and generation. The destination has its own physical
material generation. The source holding remains retained; early source reclaim
is outside this profile.

The canonical `actql-remote-retained-task-input/0.1` body contains twelve string
fields in canonical key order:

| Field | Owner or meaning |
| --- | --- |
| `consumer_input_port` | Checked consumer edge |
| `consumer_logical_cid` | Checked consumer fragment |
| `consumer_task_key` | Checked consumer fragment node |
| `destination_receipt_json` | Exact admitted Transfer destination receipt |
| `physical_input_json` | Existing standard Transfer input body |
| `producer_evidence_json` | Original durable execution evidence |
| `producer_logical_cid` | Checked producer fragment |
| `producer_output_port` | Checked producer output port |
| `producer_request_json` | Original producer dispatch and attempt |
| `producer_subject_json` | Original managed output subject |
| `run_definition_cid` | Original admitted Run Definition |
| `version` | `actql-remote-retained-task-input/0.1` |

JSON-valued fields are strings containing their owners' canonical bodies;
callers do not rebuild these bodies. The existing Remote input binding owner
applies its UTF-8 byte ceiling and canonical identity. Restoration reissues the
body from re-admitted original Run materials and recovered owner records and
requires both exact bytes and identity equality. It does not refresh the Run,
mint another attempt or reserve capacity.

## Current authority and physical borrow

The trusted Host installs `NativeRemoteRetainedInputCurrent` against its
existing Site, authority, clock and authorization owners. Its portable counterpart
`ClientRetainedInputCurrent` supplies the same checks for Cloud issuance. Saved input bytes
cannot supply those observations. Authorization covers the original Run and
edge and current source/destination Transfer grants. It must be confirmed again
on restoration and around physical borrow validation. The current generation,
runtime binding, Transfer lifetime and live producer retention are also
rechecked. This callback is an adapter trust boundary, not a grant issuer.

The consumer borrows a separately acquired destination-material reader. Borrow
validation checks its exact destination receipt and use occurrence, then uses
the existing Transfer owner to verify its physical generations. The Native
capture adapter also checks that the durable reader ID is the exact consumer
dispatch identity, retaining the consumer attempt rather than borrowing another
reader on the same destination. A failure
leaves the caller's reader and holding owners intact for reconciliation and
cleanup. Missing material, generation mismatch and unavailable authorization
are input admission failures; none asserts that a Compute executed or that its
execution outcome is unknown.

Returning a reader releases only that borrow. It does not release destination
capacity, source capacity, unfinished Transfer resources or Named Result
retention. Each existing owner confirms its own physical cleanup before
returning its reservation. Pending cleanup retains that reservation and retries
the same responsibility. Source and destination reservations overlap until
their separate cleanup confirmations; no capacity ceiling is relaxed.

## Restoration and integration limits

Coordinator reconstruction and holder replacement within one current Site
generation restore the original Run, producer/attempt, checked edge and input
port together with live Transfer custody. The journal remains responsible for
idempotent reservation and reader restoration. A normal restart that advances
Site generation cannot reuse the old input; it retains the appropriate
recovery and cleanup obligations without automatically reacquiring Source.

`prepare_client_retained_task_dispatch` accepts only the opaque owned input
and the same re-admitted Run/compilation. It derives the consumer from the
checked edge and checks current Site selection and authorization before and
after issuance. The ordinary input issuer still refuses dependent tasks that
have no such custody. This operation does not commit or deliver a dispatch.

The Native capture adapter validates the dispatch, input and original checked
producer capture owner before any physical read. Existing registered Transfer
providers supply bounded bytes and borrow lifetime; the existing row verifier
establishes the captured source. It never performs another Source acquisition.
Rejected pre-admission leaves the borrow with its caller. Stream or framing
failure returns the existing retryable physical cleanup owner. Success keeps
the borrow live until its capture owner closes; neither path reclaims a holding.

These APIs do not install a consumer executable, reserve a second holding,
restore a reader, commit a consumer dispatch, reconcile an unknown execution
or acknowledge cleanup. Actual Cloud/Native callers must connect these owners
and persist the original responsibility. Public two-task execution and
restart/cleanup acceptance require separate execution evidence, not just
admission of this canonical body or registered-provider unit tests.
