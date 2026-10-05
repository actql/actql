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

The resident physical handoff validates the exact original producer completion
and current Transfer scope before opening its output. A Direct receiver keeps
its own journal reservation and also acquires a Site holding, so its bytes share
the same Site retention ceiling with the still-retained producer. The caller
keeps one handoff owner inside its existing serialized holder responsibility.
A failed write retains the exact pending chunk and reader for retry; it does
not fetch the Source or execute either task again.

Committed receiver journal reopening compares the saved receipt and preserves
the live holder's existing Site reservation. It is not a Site restart or proof
of restoration after that holder is lost. Once cleanup begins, handoff cannot
resume. Receiver cleanup uses the existing material reclaim Owner, excludes
live borrowers, and remains available after execution authorization expires.
Restoring that cleanup duty never revives a returned reader or grants payload
access. Only confirmed physical receiver cleanup returns its Site holding;
producer and Named Result retention remain separate duties.

The portable retained-input handle installs ports to the existing current
Transfer, Site and authorization owners. It re-admits the current durable
Transfer record and exact destination receipt before issuing a binding, when
restoring saved binding bytes, and before and after consumer dispatch issuance.
Canonical equality ties restoration to the original producer and checked edge.
The historical binding projection grants no borrow, physical payload access or
start claim. Admission creates no reservation and cannot refund one.

The current Site port verifies identity, generation, runtime bundle and
availability using the trusted live owner; it does not instantiate a Site from
saved fields. The existing Native constructor delegates to its actual execution
Site. Authority, current lifetime and both Transfer grants remain separate
checks. Across asynchronous Cloud persistence and delivery, the caller must
retain its existing Owner revision fence and revalidate before sending.

The resident consumer execution entry reads the exact saved envelope and
rebuilds its admitted Run before calling a trusted retained-input restoration
port. That port must reissue the checked edge from this preparation and admit
the saved binding against the current original producer observation and the
actual committed Transfer record/receipt. Reusing an input tied to a different
preparation fails the existing capture-owner check; equal rows or schema do not
replace that check. This restoration creates neither a borrow nor a reservation.

The existing pinned borrow must name the exact consumer dispatch occurrence.
Pre-admission refusal keeps it with the caller. The Runtime rechecks the original
Run lifetime and live input custody at its exclusive start boundary, preserves
the exact claim and performs Compute through the existing retained executor.
After capture, its output cleanup returns that borrow; an unconfirmed Runtime
close retains the same Runtime for retry. A guard refusal before capture cannot
return a borrow that the Runtime never acquired. The entry does not deliver a
poll operation, publish a Result, reclaim either holding or complete Run release.

## Internal producer Transfer planning

An internal acquisition task has no public Result definition or publication
attempt. Its immutable `actql-remote-retained-input-intent/0.1` is issued from
an available original producer and its checked consumer edge. It names the
consumer input port and task, both logical fragments, producer output port and
schema, and exact original completion/managed-subject identities. Existing
Transfer/grant owners supply the separate movement policy. Protocol construction
or JSON admission alone does not establish that checked edge or authorize I/O.

`actql-remote-poll-retained-input-plan/0.1` carries the original canonical
producer dispatch and this intent. It is distinct from public Output planning,
physical handoff and consumer dispatch. The receiving Host compares the intent
against its admitted checked producer, then derives the existing Direct Transfer
request from the Runtime's actual held physical manifest. It does not open a
payload reader, allocate a receiver or start Compute during planning. Current
Site identity/generation/bundle, authority, lifetime and both grants must pass
the existing retained-input preflight before returning the plan.

The resulting `actql-remote-retained-input-plan/0.1` binds that intent and the
original dispatch to canonical managed subject, execution evidence, physical
manifest and Transfer request bodies and their identities. Readmission verifies
all nested originals and their cross-bindings, including the exact Transfer
occurrence, source material, schema/view/codec, counts and policy. This initial
profile uses one independent receiver on the same original Site generation;
it does not authorize generation migration. Physical handoff must revalidate
current Owners, rather than treating a historical plan as permission to send.

The wire schemas, bounds and fixed preimages are owned by
`spec/contracts/actql-remote-retained-input-wire.json` and
`spec/fixtures/remote-retained-input-wire-vectors.json`. String values preserve
original Unicode and newline bytes; Int64 policy values use canonical decimal
strings. Structural schema admission is followed by Int64-range, exact
canonical identity and semantic cross-binding checks. The Coordinator must
save the exact admitted intent/plan through its existing durable state and
revision fence before delivering a handoff. Failed or uncertain persistence
must send nothing. Retrying uses the same saved originals and occurrence, never
refreshed expiry, regenerated materials or another attempt.

The Run Host distribution exposes checked intent issuance and restoration as
opaque in-process handles. The issuer obtains edge and completion fields from
the original producer; a caller supplies only the separate Transfer policy.
Restoration re-admits the exact saved body against a freshly checked producer.
The poll-envelope entry rechecks that producer, so historical intent bytes do
not authorize delivery after producer custody becomes unavailable.

A reported Native plan is admitted against that intent and the original
producer's actual subject and evidence. Its current ports inspect the existing
Site generation/bundle, authority, lifetime and movement grants. There is no
receiver record at the planning stage; admission does not invent a committed
Transfer. Producer availability is checked again after trusted authorization,
so a cleanup or replacement observed during that callback refuses the plan.
Installed ports retain their functions, not their first successful answers.

Canonical plan/Transfer/manifest projections are historical evidence only.
The caller persists original intent and plan under its existing durable Owner,
rechecks its revision across awaits and revalidates the plan immediately before
handoff. Failure or uncertain persistence sends nothing. Reconstructed callers
restore the same saved originals and install fresh current-owner ports; they
do not refresh the transfer occurrence or original Run lifetime. JSON admission
and a successful plan check issue no physical holding, borrow, start claim,
consumer completion or cleanup evidence.

Native callers without an installed checked producer planning port reject this
operation explicitly and retain the producer responsibility. Wire recognition
and a Native planning/handoff caller do not establish ordinary resident holder
routing, durable Cloud delivery, Result publication or both-task Run release.

The Native plan handoff constructor joins the exact admitted plan and intent to
the original checked producer before selecting its Transfer request. It stores
that immutable pair inside the existing physical Transfer owner, rather than
creating another custody ledger. Every advance and committed-journal reopening
revalidates the checked edge and live producer after current authorization. A
producer release observed during that callback refuses receiver admission or
the next physical step. Historical plan bytes do not authorize payload access.

The constructor itself opens no reader and creates no receiver record, holding
or borrow. Physical progress, pending chunks, exact receipt and capacity remain
with the existing Direct Transfer journal and Site holding owner. Cleanup of an
already acquired receiver duty is still possible after producer release or
authorization expiry, and only its confirmed cleanup returns that reservation.

The resident control process relays an internal planning envelope only to the
live holder of that exact original producer dispatch. The holder rebuilds the
original admitted Run from its saved Site-journal envelope and selects the
checked producer using the durable completion evidence and managed subject.
This reconstruction creates no reader, reservation or borrow. Missing envelope,
foreign checked edge or absent completion evidence is a refusal, not permission
to reacquire the Source.

Local internal movement requires three explicit delegated identities:
`--retained-source-grant-cid`, `--retained-destination-grant-cid` and
`--retained-route-capability-cid`. All three must be configured together. The
execution grant and evidence issuer are not substitutes for these roles. The
holder rechecks the configured dispatch authority and live Site generation,
Run lifetime, original intent and fresh producer journal before handoff.
A durable cancellation request withholds movement; it is neither a cancellation
terminal nor proof of physical stop or cleanup. A failed journal read withholds
movement while retaining existing resource responsibilities.

The plan is reported as its exact canonical body through the existing
authenticated observation transport. Its HTTP acknowledgement is neither a
receiver commit nor a consumer execution claim. Coordinator persistence and
current authorization remain required before physical handoff; the local
delegation cannot replace the Cloud grant Owner or its revision fence. A
reported plan alone does not publish a Result or release either task.

Native callers without this installed checked producer planning port reject
the operation explicitly and retain the producer responsibility.
