# Remote retained task inputs

A dependent task receives the output of its checked producer edge, not any
material with equal bytes or schema. `prepare_client_retained_input_edge`
joins the original admitted Run to the checked producer fragment/output port
and consumer fragment/input port. The fragment identities retain the checked
schema and ordered computation. Resolving this edge issues no start claim.

The portable Run Host package exposes this edge as an opaque
`RetainedTaskInputEdge`, not a caller-authored port projection. Cloud producer
admission uses `prepare_client_coordinator_retained_input_producer`: the existing
Coordinator Owner must have durably accepted the exact dispatch, managed-output
evidence, subject and measurement, with active cleanup custody. It does not
construct a Site journal from a Coordinator observation.

The trusted Host installs an atomic current-record port. Every availability
check consults that port and the existing Coordinator observation Owner again;
reconstruction may supply an equivalent recovered record, but another attempt,
missing observation or begun cleanup cannot supply current producer custody.
The package adapter re-admits the current durable record and its history against
the current Coordinator authority. The port must read the existing trusted
Owner, not retain the first successful wire as a permanent authorization. Host
callers retain the durable revision fence across awaited physical handoffs.
Producer evidence alone establishes neither current Site generation and grants
nor an independent destination holding; the existing retained-input Current
and Transfer Owners still admit those separately before consumer dispatch.

Relation ports retain their checked Carrier contract, while physical output
admission separately derives the complete field-map schema through the existing
Relation schema Owner. An ordinary row object contract and the field-map schema
are distinct identity domains even when they describe the same required
columns. The edge projection preserves the Carrier contract;
`client_retained_input_edge_schema_cid` supplies the physical schema. Neither
identity may replace the other during producer or Transfer admission.

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
The registered codec fixes framing before reading. The standard output
export's ordered-row contract uses `[` on the first row chunk, `,` on later
chunks, and `]` on the final chunk. An empty export has exactly one `[]` chunk
with zero rows. The verifier checks those delimiters and exact manifest lengths
before passing each row to the existing typed decoder. The installed per-chunk
wire limit includes framing, and physical frame and total byte limits remain
unchanged. A malformed ordered export is never retried as a bare-row profile.
Other existing registered row profiles retain their one-bare-row-per-chunk
contract. Neither profile rewrites Transfer bytes, chunk identities, the
producer manifest, or execution evidence.

Rejected pre-admission leaves the borrow with its caller. Stream or framing
failure returns the existing retryable physical cleanup owner. Success keeps
the borrow live until its capture owner closes; neither path reclaims a holding.

The portable issuers do not install a consumer executable, reserve a second
holding, restore a reader, commit a consumer dispatch, reconcile an unknown
execution or acknowledge cleanup.

The Native adapter `open_resident_retained_compute` connects an exact durable
reader to the existing captured DAG and Native Compute Owner. It prepares the
original checked capture without opening the configured Source database, then
reserves decoding retention and execution capacity independently of both
physical holdings. The same Native task execution and cleanup methods serve
locally acquired and transferred captures. Export pins can keep cleanup
pending; returning the borrow still leaves physical destination and producer
holding cleanup with their separate Owners.

Direct and Store destinations use the same durable journal reader and material
cleanup state. Direct uses the allocation occurrence established by its receiver
and a request-scoped exact reader key. Reattaching that reader after journal
reconstruction does not allocate another holding or revive a returned reader.
The cleanup Owner can repeat a completed reclaim without another capacity
return; new reader admission remains forbidden after reclaim begins.

Actual Cloud/Native callers must persist and connect the original Run and task
responsibility. Public two-task execution, Coordinator reconstruction and
holder replacement require separate execution evidence, not just admission
of the canonical body, journal reconstruction or Native composition tests.

The Native retained consumer executor enters through the existing Runtime's
bundle admission, exclusive start claim and output evidence path. Its bound
factory admits only the exact consumer dispatch, including the attempt; another
dispatch with an equal input binding cannot reuse that borrow. Compute completion
keeps the input borrowed while output readers remain active. Formal output
release closes the captured Run and returns its borrow, after which the separate
destination and producer cleanup Owners can release their holdings and capacity.

A completed acquisition task can have an internal consumer edge without a
public Named Result rooted at that producer. Its export uses the original
captured DAG's exact physical source match and the existing Relation export
Owner. It does not fabricate a Result definition, another Run, or a completed
Compute. Public Source Results still use their checked Result projection;
internal producer output uses the checked acquisition task port. Source
observation and managed output evidence remain durable Runtime records, and
formal release closes the captured DAG before confirming input-owner cleanup.

The resident dispatch admission and execution entry derive the acquisition
role from the original checked graph and exact task key. A one-task Source Run
retains its public Result definition. The first task of a two-task Source Run
instead installs the existing internal acquisition output Owner and has no
public Result definition. Public Output admission consequently refuses that
internal output; it remains available under its original managed-output
evidence for the separate retained-input Transfer. This route does not grant a
consumer start claim or admit a consumer using the producer's input binding.
