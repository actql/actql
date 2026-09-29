# Captured Effect dependency closure: agreed 0.1 delta

Implementation branch: `feat/source-effect-run`.
This is the implementation contract, not a completion or CI claim.

## Contents and references

Extend the existing Captured Run evidence, not the public Result namespace
and not a new recovery database. The checked Effect computation selects the
acquired input and preceding Stage local Results required to validate its
Effect inputs, together with their transitive typed dependencies. Unrelated
Stages, arbitrary provider history, and unused Results are not independent
inventory roots. A referenced local Manifest still contains all Results
required by its existing contract.

Retain canonical dependency bodies, their declared contract kind and identity,
and existing Store holdings for required relation payloads. References are
derived from the admitted contract and checked dependency graph, not accepted
from a caller-authored edge list. Shared dependencies occur once in the
inventory under an exact `(kind, CID)` key. Equal canonical bodies used in
different typed roles do not substitute for one another. Audit authentication
and physical custody remain outside local
semantic preimages. A Run-bound Invocation or Manifest cannot substitute for
its local semantic counterpart.

The existing checked owner issues the closure. Recovery admits the complete
closure before using any saved local Invocation or Artifact. It rejects missing
bodies, duplicate kind/identity pairs, wrong kinds, altered bodies, foreign checked
owners, dangling references, cycles, and dependencies outside the selected
closure. A CID is not a capability or an attestation. Typed relation values
terminate the graph only after validation against their retained payload and
schema. Recovery does not fetch Source or rerun Compute to fill a hole.

## Bounds

The initial installation ceiling is 4,096 distinct dependency entries,
16 MiB of total canonical evidence bytes, 65,536 references, and 64 dependency
edges on a path.
Existing stricter wire, node, JSON-depth, Store-capacity and relation-payload
limits also apply; these ceilings never increase an existing admission budget.
The evidence-byte ceiling includes the inventory envelope and embedded bodies.
Payload bytes remain charged to existing Store holdings and reservations,
not exempted by keeping them outside the evidence envelope.

Issuance measures before serialization/storage allocation. Recovery checks the
bounded envelope before body admission, checks count and aggregate bytes before
building indexes, and walks the typed graph with explicit depth/work bounds.
Neither cyclic references nor repeated sharing can bypass accounting. Test the
exact limits and one-over cases independently of the production issuer.

## CID and compatibility impact

| Contract/body | Impact |
| --- | --- |
| Captured Run Effect context | Required dependency inventory changes its body and CID. |
| Captured Run | Its containing body and CID change with the Effect context. |
| Final Receipt and other exact capture references | Reissue from the new capture; never retain a stale referenced CID. |
| Local Invocation, Artifact, Manifest | Existing preimage rules remain; actual observation/upstream dependencies affect their CIDs. |
| Captured Run schema and registry | Regenerate schema pins, embedded schemas and public/generated bindings. |
| Independent vectors and fixtures | Update complete bodies and independently calculated identities together. |
| Existing Program and checked Unit definitions | No identity change merely to add durable custody metadata. |

Keep version 0.1 by explicit agreement. This is an incompatible coordinated
development change, not wire compatibility. New writers always emit the required
inventory, including an explicit empty inventory when no upstream dependency is
required. Readers reject a missing inventory, old or mixed shapes, and claims of
empty inventory when typed references require dependencies. Do not supplement
old records, rewrite their bytes, replace old signed fields before validation,
or infer permission to retry from a format rejection.

## Durable point and ownership

Before capture is complete, acquisition and Compute owners retain responsibility
for partial physical work. A crash with incomplete inputs is not a completed
captured Run. The no-reacquisition/no-recomputation boundary begins only when
all required input/result payloads, dependency bodies, holdings, the Captured
Run, and the matching Preview are durable through the existing Store path.
Publish commit approval wait only after that boundary.

A failed persistence operation retains existing cleanup responsibility and must
not expose an answerable continuation claiming successful persistence. Resume
uses the saved approval target and verifies current commit permission, Site
generation, installation, Mapping and target state. Target confirmation reads
are separately counted from Source reads. A missing or invalid dependency never
authorizes substitute input or a new computation.

Cancellation or rejection before mutation retires unpublished holdings through
existing cleanup owners. Failed deletion retains a retry handle. If a write may
have occurred, keep the exact dispatch, response or unknown correlation and all
evidence required for reconciliation. Cleanup, status, repeated answers and
restart never resend that write.

## Acceptance and handoff

Use an independently authored expected inventory. Cover upstream-body deletion,
mutation, foreign replacement, duplicate entries, cycles, unknown kinds and
bounds. From public approval wait, restart and approve the same Run with Source
acquisition and Compute counters unchanged. Count target confirmation reads
separately. Exercise persistence failure before wait, cleanup failure and unknown
write recovery without evidence loss or resend.

D received the agreed delta in PR #53 before executable handoff. C owns schema,
compiler, checked owner, Store connection and Host changes. D owns provider
adaptation. A pushed executable SHA, commands and explicitly unconnected parts
will follow; this document does not claim the acquired Effect path is complete.

## Agreed dynamic Result import observation

The static Result import interface binds producer definition and type, not an
actual produced value. The approved incompatible 0.1 addition is
`actql-result-import-observation/0.1`, with `consumer_unit_definition_cid`,
`input_name`, `import_interface_cid`, `producer_local_manifest_cid`,
`result_artifact_cid`, `version` and `self_cid`. Hash the complete canonical
body excluding only `self_cid`. The consumer input position is material.

The actual common read owner must bind the retained producer input to the
checked import. Producer Artifact and complete local Manifest precede this
observation, which precedes the consumer local Invocation. The consumer
Invocation itself is not in the observation preimage. Current Run/namespace
membership and input-use authority remain separate exact-owner checks.

The observation is retained as a typed dependency body in the same inventory;
it is not an opaque exemption from closure checking. Missing or inconsistent
Manifest/Artifact, exchanged input positions, a different same-typed output,
or absent upstream bodies reject recovery. No compatibility supplementation
or Source/Compute repair is permitted. Issuance, schema, pins, independent
vectors, complete inventory and restore admission are one coordinated change;
schema/vector success alone is not executable handoff evidence.

## Result import implementation checkpoint

The working change now issues Result import observations from the retained
physical input owner, the exact producer Artifact and its complete local
Manifest. Consumer Invocation issuance requires the complete checked import
set, rejects duplicate input positions and rechecks live custody. Artifact
custody uses the exact Run, producer and checked Result port, not an Effect
member number or equality of payload CIDs. The issuer does not establish
current execution authorization.

Focused working-tree validation: `run_publication_host` JS tests passed
16/16, including six independently fixed observation preimages; the rebuilt
Node bridge tests passed 27/27, including acquired input retention and
multi-Stage export ownership. These are not fixed-SHA delivery evidence.

Still pending: dependency-body durable Store inventory and recovery admission,
and end-to-end restart without acquisition or Compute. Upstream Artifact
derivation and the Host's temporary Store export path are now connected.
The coordinated 0.1 change remains uncommitted until those
consumers are aligned. No executable handoff or Linux CI success is claimed.

Static dependencies now have bounded serialization from the same checked
owner: local Unit Definition, Stage semantic body, used declarations/values,
local contract selection, Result import interface/type and incoming gates.
The existing emitters and cached identities are reused; no second compiler,
caller-supplied replacement body or changed semantic preimage is introduced.
The retained typed body records its exact checked owner and Unit coordinate.
The new Node bridge entry is `clientProgramEffectLocalDependencyBody`.

Additional working-tree checks: Program checker JS tests passed 337/337;
the real acquired-input bridge test passed with canonical body/CID checks
for both Units and the producer-to-consumer import reference. Three-target
interface generation succeeded. Full affected gates and Linux CI remain
pending until the coordinated inventory/recovery connection is complete.

Acquired root provenance now carries the checked static request body,
Source input/observation, Acquisition scope/Relation and ordering evidence.
The root Artifact issuer checks the retained capture identity and the exact
export preparation/receipt. Restricted lifetime handles retain the same
capture owner; handle object equality is not substituted for that check.
Source-free Artifact issuance explicitly rejects acquired/imported Units.

The focused real-DuckDB bridge case now passes through root Artifact and
Manifest issuance, Result import observation and consumer Invocation.
Independent exports cannot exchange receipts, and missing imports reject
Invocation issuance. This working-tree test passed 1/1. It does not yet
prove durable dependency inventory or restart recovery; those remain the
next connection work before the executable D handoff.

The consumer issuer now retains typed import observations and their derived
Acquisition Relations. It requires the exact inventory, complete imports,
live producer custody and current exported Result receipt. The resulting
Artifact carries the actual upstream Relation CIDs, rather than an empty
derivation or a caller-provided list. Its scope remains the one admitted
Source scope in this profile; it does not union authorization decisions.
The acquired bridge test passes through both producer and consumer Artifact
and Manifest issuance, with wrong-Unit and wrong-export rejection. Durable
inventory assembly and restart validation remain pending.

After consumer issuance was connected, the complete Node bridge test file
passed 27/27. JS/Wasm/native interface generation completed from the same
working tree. These are local checks, not final-SHA CI or restart acceptance.

The private dependency-graph validator now checks exact kind/identity,
missing and unused nodes, cycles, aggregate bytes, entry/reference limits
and longest-path depth even with shared subgraphs. Root references consume
the reference budget as well. Publication package JS tests passed 150/150.
The graph validator is now called by typed dependency-body validation.
Publication bodies use the existing strict decoder; local Invocation,
Manifest, Result Definition and import observation use closed canonical
shapes and self-CID checks. References are extracted from those bodies.
Root selection still requires the checked owner and is not recovery
authority. Captured Run/Store admission is not yet connected, so this is
not counted as completed recovery validation.

Publication package JS tests now pass 152/152. New reader cases use the
independent import-observation vector, reject changed/missing input position,
Artifact replacement and injected edge lists, and reject missing scope
dependencies. Static checked-body and retained-payload admissions still need
to join this inventory before the durable boundary can use it.

Saved static body admission now matches exact canonical bytes against the
typed body issued by the checked Program, Unit and dependency kind. It
returns the existing token without hashing, compiling or executing again.
Foreign owner/Unit and altered or noncanonical text reject admission. The
Host bridge exposes this check next to the existing body issuer. Program
checker JS tests passed 337/337 and the real acquired-input bridge case
passed 1/1 with saved-body checks for both Units. This is still a component
of recovery, not a completed Store inventory or public restart route.

The bounded inventory envelope now serializes entries as canonical
`{body, cid, kind}` objects ordered by CID. Reading rejects noncanonical
bytes, unknown or extra fields, foreign identities, missing roots and unused
bodies before returning an inventory token. Total bytes include the JSON
envelope, not just the embedded bodies. An independent empty-scope fixture
covers exact byte capacity and one-byte overflow. Publication package JS
tests passed 153/153. Static-body/payload admission and the Captured Run
caller remain outstanding; the envelope token does not grant recovery.

Local Unit Definition and Result import interface readers now derive typed
edges to static bodies, declarations, contract selection, gates, producer
Unit and imported value type. Closed Unit namespace and `stage_success`
availability checks remain mandatory even when an invalid body is rehashed.
The actual checked-body fixtures pass through these readers (Program checker
JS 337/337); Publication JS 154/154 includes rehashed invalid-shape cases.
No Store/public restart completion is implied by these reader tests.

Source Evidence and Source Input Logical now enter the inventory through
the existing generated-protocol admission and identity checks. Their typed
edges retain the exact input, source, schema, capability, policy and Source
View references. This does not reauthorize acquisition. Source-body fixture
tests reject changed observation text, wrong body kind and noncanonical
bytes; Publication JS remains 154/154. Static/payload completion and the
Store caller are still required before executable handoff.

The Host now carries acquired evidence from its publication plan into the
existing Effect source exporter. Required local Results are exported in checked
producer order. Each complete producer Manifest precedes import observation
and consumer Artifact issuance. Member association checks the exact retained
Result occurrence; an upstream-only Result is not fabricated as an Effect
member. The publication-plan ABI remains unchanged.

The real acquired-input Node bridge case now uses the real Publication Store
for both Results after Compute completion. Injected consumer reservation failure
plus producer release failure preserves the primary cause and a retryable
cleanup owner. Cleanup finishes without new reservations. The complete bridge
file passes 27/27 locally after this connection. This proves prepared payload
custody, not durable capture/restart: the required dependency inventory still
has to enter Captured Run issuance, Store custody and recovery validation before
approval wait is published. No pushed executable SHA or final CI is claimed.

## Captured context and import recovery checkpoint

Captured Run issuance now writes the required `effect_dependency_inventory`.
Its roots come from the captured local Effect sources, not a supplied root
list. Values-only issuance emits an explicit empty array. Missing inventories
are rejected on recovery, and an acquired/imported input cannot be issued
with an empty closure. The generated protocol enforces the 4,096-entry ceiling.

Closure admission also verifies import correspondence using the already
admitted bodies, without reparsing or rehashing them. Consumer Unit, import
position/interface, producer namespace, Manifest, Artifact and Result
Definition must agree. Every checked Result import must have its observation;
each Manifest entry must belong to its exact local Invocation and Unit.
Integrity alone does not authorize recovery or establish payload custody.

Focused Publication, checked Program and publication Host JS-target tests
passed 511/511 at the intermediate working state; the schema/generator Node
tests passed 16/16. Generated API interfaces were refreshed for all three
targets, and document/schema metadata validation passed. This is not a fixed-SHA
handoff or CI result. Static/payload leaf completion, upstream durable Store
holdings and the complete Host recovery caller remain unconnected. The
member-only holding path continues to reject incomplete upstream custody.

## Prepared dependency custody checkpoint

The existing completed Result owner can now adopt the required upstream and
member payload preparations from the exact exported Effect source set. The
local Artifact issuer retains physical CID/byte facts from its admitted export
receipt; the Host checks those facts and the current Run before adoption.
This does not change the Artifact semantic preimage or rehash/reexport rows.
Foreign Artifact wrappers, another Run, duplicate adoption and released
preparations are rejected before ownership transfer.

The real acquired Program bridge test now transfers both local Results to
that completed owner. A one-shot failure in the real Store's post-unlink
directory sync leaves the upstream payload pending with a cleanup handle.
Retry completes that same deletion, releases both payloads and allows the
completed owner to finish; no new export is performed by cleanup. This is a
process-local custody and failure-recovery test, not restart acceptance.

Durable capture still fails closed for these newly adopted payloads until
dependency inventory, physical holding and recovery validation are connected
together. Merely adopting them cannot expose resumable approval wait.

The checked-body issuer also exports the exact Check Environment schema and
capability members referenced by Source Evidence. Their identity hashes the
complete member body; it is not the Source View's self-excluding contract
identity. The same checked Program/Unit owns issuance and saved-byte admission.
This is body custody, not fresh read or commit authorization.

The acquired-input bridge regression checks both member bodies against the
actual acquisition's evidence CIDs, canonical bytes, foreign Unit rejection
and altered saved-byte rejection. The focused bridge test passed 1/1 after
rebuilding local-node; the focused checked-body JS test also passed 1/1.
These intermediate checks do not establish durable inventory/restart
completion or a fixed-SHA handoff.

Dependency inventory readers now admit complete canonical schema/capability
members, Relation schema and tagged logical Relation bodies. The logical
Relation reader rejects physical row arrays, a different sort and changed
rows under an unchanged identity. These are integrity checks; checked owner
and retained-payload binding remain separate requirements. Captured Run's
schema pin is now
`sha256:525bc713312ad19b992b4fe66322f33d5c6e606d678fea5167e8196510a0c1c9`.
The expected pin was calculated with independent recursive canonical JSON
and Node crypto, rather than copied from the product identity function.

The checked-body issuer also exposes exact Source View and registry contract
bodies. Unlike observation members, their existing identities exclude the
contract's own identity field. The real acquired-input bridge checks those
preimages and matches the Source View to the acquisition evidence. Focused
bridge 1/1, Publication JS 159/159 and schema/generator tests 16/16 passed.
An initial generator/test invocation without the pinned toolchain PATH failed
to find moonfmt; rerunning with that PATH succeeded. Store materialization
and complete recovery remain outstanding, and no final CI is claimed.

## Retained export body connection

The dependent Effect exporter now retains each required local Result's tagged
logical Relation text from the same chunks written to its prepared Store
object. The schema body comes from that exact export receipt before receipt
release. It does not read the provider or execute Compute again. An aggregate
16 MiB UTF-8 text budget is charged before retaining chunks/schema text across
the entire export set; final inventory admission additionally accounts for
other evidence and the envelope. This byte budget is not a claim about exact
JavaScript heap usage (strings and joining have bounded additional storage).

The acquired multi-Stage test compares producer and consumer bodies with
independent expected rows, checks their logical identities and distinguishes
them from physical object identities. Existing failure cleanup still owns
prepared objects; retaining text does not transfer or release those owners.

The shared Captured Run bridge now accepts an optional dependency envelope
and admits it against roots derived from typed captured local sources. It
does not accept a caller-supplied root list. Node and Workers wrappers are
regenerated from the shared template. Full publication-control and Client
bridge tests passed 38/38; Publication JS tests passed 159/159. The completed
owner's incomplete-capture guard remains until physical durable holdings,
the complete closure and recovery are connected. This is not executable
restart acceptance or a D handoff SHA.

## Catalog and retention body checkpoint

Inventory integrity admission now includes selected Source View/Source
contract bodies and data-policy Catalog envelopes. Their self field is
excluded according to the existing contract identity, unlike the complete
schema/capability member hash. This does not replace checked Catalog closure
or current authorization checks. Restoring the complete closure and its
physical custody remains an outstanding Host responsibility.

Local retention references formerly hashed the insertion-order JSON
`{version,name}` without retaining that text. The three retained policy
bodies now use canonical `{name,version}` and are carried by the acquired
publication context into the dependent export set. Their fixed identities:

- `local-result-retention`:
  `sha256:a8fb82bdb39b1eb3e6871a55d63f3cb554dcc1953e06501bb686fd8ca8f9646a`
- `local-result-metadata`:
  `sha256:dbf36e9f6f9b35881ac625290a1c93dbbe485ee8d954cdac3c55e345df4c3095`
- `local-clock`:
  `sha256:c2f7278baa9548283e904d1e8b9048efc0a206ecaca397527ec970776a2f2356`

This changes the newly issued retention body and transitive Artifact/Captured
Run identities for ordinary Local publication too. It is not compatible with
the previous opaque profile hashes; no old-ID substitution, saved-record
rewrite or retry authorization is introduced. Other installed policy IDs and
Run identity rules are unchanged. The names and retention time calculations
are unchanged. Independent literal hash vectors and actual acquired Plan
references check the coordinated transition.

The current Captured Run schema pin is
`sha256:7b3d173c3a078431c99352e3bac4e5a2341ea2217c1995ab8c97dd9c56027ac1`.
Publication JS passed 161/161, Local Plan/Client bridge 32/32, and schema plus
generator tests 16/16. Documentation metadata and schema pins were regenerated.
These are intermediate local checks, not final fixed-SHA or Linux CI evidence.

## Export-set inventory assembly checkpoint

Each selected Unit now emits its complete static Invocation dependencies
through the original checked owner: Unit body, parameter declarations/values,
contract selection, policy, exact import positions/types and incoming gates.
Entry and aggregate byte limits apply before the complete list is returned.
The exporter shares those bodies among that Unit's Results, with a separate
4,096 static-entry budget rather than consuming the member-grouping budget.

The owned export set now reaches a shared inventory preparation boundary.
Roots come from typed local Artifact owners; copied wrappers and foreign
export sets reject admission. Body classification and canonical graph
validation remain in MoonBit. Exact repeated bodies are coalesced by kind
and identity when constructing the inventory, whereas duplicate entries in
a saved inventory still reject. Aggregate input bytes are bounded before
another body is admitted. The Captured Run caller rechecks its exact source
roots; this preparation is not authorization or proof of durable custody.

The actual acquired two-Stage case verifies static body roles and the exact
consumer import interface. Its incomplete acquisition closure is rejected
before capture, rather than being repaired or exposed as approval waiting.
Publication/checked Program JS tests passed 498/498 and the focused actual
acquired bridge test passed 1/1. Acquisition/Catalog body assembly, durable
holdings and the completed recovery route remain to be connected.

### Acquisition payload retention checkpoint

Effect acquisition now retains its canonical Relation and schema bodies in
the existing identity traversal, under an aggregate 16 MiB body limit. It
does not reread the provider or export the acquisition a second time. The
getter requires the exact live capture owner; matching content from another
capture is insufficient. Ordinary read-only identification keeps its previous
non-retaining behavior. These bytes are preparation evidence, not durable
custody, authority, or an additional physical memory reservation.

The DuckDB Source adapter selects
`clientProgramIdentifyCapturedEffectSourceRelation` for Effect owners.
Other Source adapters must select this same common entry when preparing an
Effect acquisition; D should use it instead of adding a provider-specific
identity implementation. `clientProgramCapturedSourceDependencyBodies`
returns the retained logical Relation and schema only for that capture.
The publication plan and dependent export set carry these bodies alongside
the independently retained computed Result bodies. No saved-data fallback
or provider reacquisition is introduced.

The actual acquired read and two-Stage Effect bridge tests passed 2/2,
including independent expected input rows/CIDs and foreign-capture rejection.
Local runtime generation and three-target API generation succeeded. These
are working-tree checks, not a pushed fixed-SHA or Linux CI result.
Catalog closure assembly and durable capture/recovery integration remain
unfinished; the fail-closed publication guards are still present.

### Complete acquired dependency assembly

The actual acquired two-Stage case now issues its complete canonical
dependency inventory. The admitted Source observation selects schema,
capability, Source View and policy bodies from its original checked owner.
Lookup is bounded to 4,096 members per selected Catalog section and selected
body text shares the caller's byte limit, capped at 16 MiB. No adapter-supplied
Catalog text or provider refresh fills a missing dependency. The exact
request CID comes from the checked Query material, not a second hash pass.

The inventory includes the Source's retention body and the required static,
acquired and imported Result evidence. Only producer Manifests referenced by
actual import observations are included; the terminal Result's own Manifest
is not an extra dependency. Shared kind/CID bodies are coalesced at assembly.
Saved duplicate entries remain invalid. Inventory admission still derives
roots from typed owned Artifacts and checks every import edge in MoonBit.

The real acquired bridge regression checks the two Stage/Result identities,
the single imported Manifest, independent logical row preimages, and exact
Catalog body correspondence. Missing Source/Catalog/import evidence and
changed input bytes reject. Rehashing a same-typed replacement does not make
it the observed input. The full bridge file passes 27/27; checked Program
and Publication JS packages pass 337/337 and 161/161. An initial file-filter
command selected zero MoonBit tests; it is not counted as verification.

At that checkpoint these checks established preparation only. The following
checkpoint supersedes the outstanding physical-custody integration above.

### Durable capture and public HTTP checkpoint

The completed owner now adopts the exact dependency payload owners before
member holdings are committed. Its existing capture holding retains the
union of public Result and required local Artifact payloads. The private
capture record requires `effect_dependency_payloads`, binding each required
Artifact to its verified physical CID and byte count. This is physical
custody metadata, not a new semantic identity or execution permission.
Recovery and retirement validate the complete binding inventory against the
admitted Captured Run and its exact holding. Missing old-format fields are
not repaired. Public contract CID rules are unchanged by this private field.

The actual two-Stage bridge test commits capture, closes and reopens the real
Store, recovers the same Captured Run and inventory, and retires its owners.
The focused test passed. The public HTTPS reference-Site test additionally
passes acquisition, two-Stage computation, durable approval waiting, Host
restart, approval, four writes across two members, and Named Result reading.
The acquired Invocation bridge now returns the original issued owner for
Preview binding, matching the source-free owner path; it does not reissue it.

These are working-tree tests, not a pushed SHA or Linux CI result. The new
HTTP test counts capture/recovery factory calls. The additional
`node scripts/test-acquired-effect-computation-probe.mjs` wraps the real
shared Compute entry before Host import and asserts exactly one initial
call across both approval and post-success Host restarts. This probe passed;
it does not use best-effort diagnostics. The final restart also reads the
same Named Result and confirms the four writes have not increased.
The acquired response-loss case interrupts the Host on the final row after
three durable successes. Restart preserves `needs_reconciliation` and no
Result publication, with no additional dispatch or Compute call. Both cases
are executed by the probe driver. This is distinct from a provider adapter
handling a row failure and continuing independent members: an uncaught
physical callback failure interrupts this reference Host invocation.
The installed continuation now also requires `unit_id`. Initial issuance
uses the Effect Unit in the original checked compilation; recovery compares
it with the journal's admitted `run_unit` subject before claiming resume.
There is no fallback to the former hard-coded `values` label for saved
continuations. This is a coordinated private 0.1 record change, not an old
record migration. The HTTP test asserts `compute_a` at both authorization
entries while preserving the public Checkpoint summary projection.
Failure-path, packed/Embedded and final gate evidence remain pending.
No executable D handoff is claimed yet.

After these changes the complete `remote-checkpoint-host.test.mjs` file
passed 47/47 (44 top-level cases) in about 141 seconds. It includes existing
Values cleanup, cancellation, expiry, revocation and independent-member
coverage as well as the new acquired success and interrupted-unknown cases.
This does not turn the existing Values failure cases into acquired-input
coverage, nor replace packed acceptance or final-SHA Linux CI.

The acquired-input cancellation and rejected-answer cases now also pass
through public HTTP after the first Host restart. Both use the existing
`cancelled` waiting-exit outcome for a never-dispatched continuation. After
a further restart, all physical holdings and object payloads (including the
upstream-only Result) are gone, capture ran once, provider recovery was not
entered, and writes remain zero. Focused tests passed 2/2. This supplements,
rather than substitutes for, expiry and cleanup-fault coverage still needed
for acquired dependency custody.

### Specification job checkpoint

`node scripts/local-checks.mjs run spec` reached canonical generation after
passing its preceding checks, including 1,049 execution-Relation tests. It
stopped at stale `identity_vectors.generated_test.mbt` output (376 seconds
for the job prefix). Regenerating with `check-canonical-json.mjs --write`
restored the generator-owned file; no expected CID was manually adjusted.
`npm run check:canonical` then passed 325 identities and 23 tests. Every
remaining command after that boundary in `package.json`'s `check:spec`
sequence passed. The expensive successful prefix was not repeated.
This is a split local validation with a recorded generation correction,
not a single clean final-SHA spec job or Linux CI success.

### Common contract and Host custody checkpoint

Shared contract commit `c0ccc561d7395a3146b815edf7f3fa5f9b79172d`
contains the checked dependency identities, schemas, pins and vectors.
Core JS passed 6,962 tests; formatting and generated three-target API checks
passed. Wasm/native execution and final integration gates remain pending.

The subsequent Host/Store working tree passed the complete bridge,
Publication Store and installed Effect Site tests together: 101/101.
`node scripts/test-acquired-effect-computation-probe.mjs` also passed all
four public HTTP scenarios (success, unknown, cancel, reject). Each observed
one actual initial Compute call and zero calls across its restart paths.
These local results do not establish packed/Embedded acceptance or Linux CI.
