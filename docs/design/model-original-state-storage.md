# Private storage of original Model state

`original_model_state` is a dedicated role of the existing encrypted Local
continuation evidence Store. It is not `captured_input`, a Source capture or a
published Result. The trusted Host connects the existing original resource
Writer to this role; storage does not manufacture a resource state from JSON.

The existing storage binding is closed by owner ID, original request/Run
Definition CID, exact role, semantic byte CID, derived physical holding,
namespace and installation key generation. `hold` records that custody before
committing ciphertext, verifies the exact bytes from the physical Store and
returns their semantic CID only afterwards. A lost reply does not justify
re-running the Writer or Model. The same original holding can be reopened and
verified; missing evidence remains unknown.

Read rechecks request/key/role/holding/state, physical size and AEAD/content
identity. The saved original bytes are not passed through a configuration
canonicalizer. Neither a CID nor successfully read bytes admit a current
Ledger, restore a token, reset a budget or authorize Model dispatch.

The holding preimage remains `actql-local-continuation-holding/0.1` with the
existing fields `version`, `prepare_attempt_id`, `name` and `semantic_cid`.
The new exact name distinguishes its custody; old names, preimages and CIDs
are unchanged. Its existing encryption AAD binds that name and semantic CID.
There is no self CID in the stored original bytes. This role addition does
not add an owned Model artifact/schema or change the original data codec.

The resource Owner separately issues and admits the closed original
read-snapshot/checked-plan binding and, later, the current resource cut. Those
contracts and their schema/pin/vector changes must be registered together.
This storage primitive alone does not authenticate those semantics or link
a preparation basis to a later Slot/Entry/Run revision. Host startup, the
original Writer caller's actual Store ACK and current restoration remain
distinct integration steps, not capabilities implied by role registration.

## Retirement

Generic terminal status and abandoned preparation do not release this role.
Retained Results, Unknown calls, reconciliation and CleanupPending may still
need the original state. Missing release observations, including after restart,
keep custody. The current storage primitive deliberately excludes this role
from automatic terminal retirement; no caller Boolean or arbitrary callback
can make it releasable here.

The later connection must use the same original Owner's issued release facts:
read/Writer settlement, whole-scope finish, no unresolved calls and no remaining
Result need. A failed deletion retains the original Store cleanup handle and
durable pending record. Holding encrypted bytes does not transfer ownership
of a retained Model token. The exact release issuer is not connected by this
role-only change, so whole Model state reclamation is not established.

Object byte limits do not bound retention metadata or revision discovery.
The installation must fund those acquisitions and all Writer/string/UTF-8/
Store/AEAD/read/ACK overlaps before public use. This role does not introduce a
numeric profile, fallback ceiling, resource pool or separate Owner.
## Private original metadata acquisition

The existing trusted Model installation may retain an optional
`metadataAcquisition` declaration alongside its original read installation:

```text
{
  metadata: {maxWireBytes, maxLedgerEntries},
  directory: {maxWireBytes, maxDirectoryEntries},
  retainedBytes: Int64-compatible positive bigint,
  workspaceBytes: Int64-compatible positive bigint
}
```

The four acquisition limits are explicit finite safe integers; byte limits are
positive and entry counts may explicitly be zero. All retention revisions,
including retired entries, count. Directory entries and cumulative UTF-8 name
bytes have separate limits. Unknown counts are not zero or unlimited. Provider
metadata limits and Store object limits are not substitutes. No default
numerical profile is installed by the presence of these declarations.

The installation snapshots and freezes this data before Run start. Its original
nominal membership and exact five-field `nodeInstallation` selection are kept;
an equal object, copied declaration, public packet, CID or Bool cannot select it.
The operation captures that same installation through
`originalPreparation.metadataInstallation`, with its existing checked Run,
Scope and original read. Complete simultaneous retained/workspace amounts must
cover all original holders and physical/decoder/queue overlap, not just one
metadata buffer. Acquisition clamps neither calculate nor reserve that envelope.

Only this original operation issues a stable private acquisition handle for its
current park. The selector rechecks both existing Model/Resource Owners and the
same read token's retention/execution coverage before I/O and after physical
awaits. Optional owner-id/request-CID checks use the actual original Run ID and
Run Definition separately. The returned immutable limits are data, not read,
restore, COMMIT, approval or send authority. Dispatch admission may remain None.

The handle weakly borrows the operation's four-field record
`park/selection/handle/current`. Installation snapshots, selector/control frames,
captured original references, source/UTF-8/parsed trees, directory backing and
queues must be funded before allocation. Failed cleanup retains that record;
actual successful operation cleanup clears it. Closing/cancellation refuses new
acquisition, while the physical Owner's same-FD/directory retry remains separate
and keeps its custody without requiring a new selector or INFER permission.

This initial seam is current-cut/parked acquisition only. It does not make
Source/general Evidence or Model prime-before-park depend on a park. Those
startup lifetimes require their own existing-Scope funding connection. Missing,
foreign, insufficient or unjustified original installation is unavailable;
neither this seam nor its component fixtures establish a normal numerical
profile or public INFER acceptance.

## Completed restored Model task in its original Effect Host

A restored Model input is authenticated by its nominal saved call scope and
the actual retained-input identity scan. It does not issue a new keyed Source
observation. The original Model execution may finish that input and its checked
Compute suffix before its enclosing Effect Host borrows the completed task.
The Host retains the same Plan, Run, generated sequences, Source holdings and
Effect dependency ports; it does not recompile or mark omitted ancestors as
newly executed.

When the installed original observation requires input dependency bodies, the
restoring caller forwards the same checked `inputBodyRead` through its existing
start boundary. As on the live path, the first identity scan retains those
bodies only after the original Read/consumer/Run capacity check. Observation
borrows that scan's actual receipt; it does not reopen input or scan it again.
Omitting the optional Read preserves the existing body-free path. A foreign
Read, insufficient capacity or cancellation cannot authorize body construction
or Model dispatch, and the original cleanup owner remains responsible.

Restored Model publication can borrow the same authenticated Saved scope and
the enclosing computation's actual retained Result-import evidence. It checks
the original compiled Run, Plan, input artifact, effective inputs and named
observations, then each checked import's original owner, producer, interface,
borrow and Manifest. The Model Invocation retains those import observations;
their existing Relations and acquisition Scope keep the Source ancestry.
The producer Artifact also retains its actual acquired-Source witness through
the import owner. The receiving helper matches that witness's Source identity
to the real captured producer, then checks its logical input and Source
evidence against the Saved observation. A shared input name, Run identity or
equal logical rows alone cannot establish this correspondence.
Historical observations alone cannot create direct acquisition evidence, and
this path neither admits live Sources into a Saved input nor reopens a Source.
Current custody is checked again before returning the borrowed publication.

For the existing separate-task plural Model form, the same Plan retains the
complete ordered graph and Scope inventory. Cold restoration borrows a nonempty
ordered subset of actual completed members; unsent members keep their existing
Local tasks. Every output still binds its own original graph, saved scope and
parent Ledger. A planned keyed input alone never becomes a retained output.

The caller retains the existing opaque Model `OutputUse` before the fallible
Host entry. The bridge accepts only the actual completed execution with the
same compiled Run, Definition, Plan and live saved scope. The Model domain
also checks its actual original Ledger against the managed parent's Ledger;
equal limits or matching identifiers do not replace that parent. The existing
managed Host opening/captured fields admit one Host, including through reentry.
A Model already bound to its original Local component remains a valid producer;
that component flag is not reused as a second output-transfer state machine.

The DAG borrows the actual task completion under its original owner and target,
leaves the deferred keyed Source slot unissued, and preserves downstream Result,
Preview and current checks. It neither consumes another attempt nor reserves a
second output allocation. The original Model execution keeps its work history,
allocation, retained input and cleanup duties. The caller releases its output
use only after the Host's consumers retire. Constructor failure, a stopped DAG
or release of this use alone does not acknowledge the Model's physical cleanup.

The cold JS caller drives the same restored operation before opening this Host.
It claims the existing `restoreRead` once, keeps the original durable Entry and
settlement callbacks, and retains the completed capture before acquiring its
additional Host output use. A waiting checkpoint returns the same computation
custody without opening a Host. An already-selected asynchronous profile uses
its existing nominal IO notification on that same operation; stop and cleanup
retire the notifier without granting dispatch or inventing an IO acknowledgement.
Fresh components continue to be driven by Local;
a saved non-keyed Plan keeps its existing Host entrance.

Publication projects the original Source leaves from that same nominal saved
scope after the combined compiled/Definition/occurrence/Plan/current check.
The private control unwraps the actual compiled and Definition tokens and wraps
the returned evidence in its existing evidence namespace. Matching the actual
direct captures identifies the remaining original keyed leaf; neither wire
parsing nor a Source name issues another observation. A changed direct leaf or
an incomplete inventory refuses publication. The original Source custody stays
live through this borrow; this projection issues no read or capacity grant.

Cold Host retirement precedes Model alias retirement. The existing computation
custody holds the output use across constructor rejection, an absent wrapper,
and a throwing cleanup callback. The managed parent's original captured DAG
retains partially constructed consumers before fallible configuration. Its
existing stop, reverse output close and retention refresh engine is shared by
returned-Host and partial-parent cleanup. Construction reentry remains pending;
a foreign parent cannot retire these consumers. False or throwing retirement
keeps the same pin and cleanup continuation for retry. Only actual consumer
retirement permits release of that pin, followed by the original Model cleanup.
It does not acknowledge Source, Store, Model or parent physical cleanup.

A completed publication plan therefore does not run the fresh path's early
Model-alias retirement while the cold Host still borrows its output. Result and
Effect consumers keep the same backing until their original cleanup returns.
These lifetime connections do not derive a numerical allowance from a saved
scope, output use, matching CID or spare Ledger capacity. The selected parent
must still fund the simultaneous constructor, original output and failed-child
backing before physical construction.

For an actual checked source-free Program, the saved Model closure has no
Source capture to reopen. The continuation first validates the same saved
Definition, unit, submission, empty Source inventory and completed capture
position, then confirms zero acquisitions from the original checked Program.
It does not open an unissued Source-capture ledger in that case. Model input,
Model evidence, Effect review and their physical custody remain separate;
nonzero or mismatched Source inventories retain their existing storage refusals.

### Same-Request material normalization and authoring originals

The original prepared/compiled material issuer borrows its already issued
Common normalization journal. Supported Effect-free/INFER profiles carry its
exact complete bytes in the existing optional `normalization_journal_json`
field. This is the intentional private-profile extension of the earlier
Effect-only use, not another wire version or an assertion that old bodies
contained the field. Changed material bytes take their natural content identity;
Program, Request, Run and evidence identities retain their meanings.

The installed inverse uses the same physical restoration Request, its original
input and the journal-selected Request/Definition pair. It stays `Selecting`
across the bounded material read, original constructors and compiler, so current
callbacks cannot reenter preparation or retirement. Before compilation, its
normalization callback funds the original occurrence audit and admits the saved
journal's integrity, catalogue, paths, rules and authored/canonical pairs. It
compares complete saved bytes; it does not rewrite the Program, issue a current
replacement journal or resolve a Source/Model. Only the complete saved
compilation/admission/Run match permits the restored original to escape.

Audit container/path demand comes from the same prepared value's retained
compiler/source dimensions, using the existing collection and normalization
representation laws. The retained sequence fold's counted original visits are
not a caller work maximum or runtime debit converted into memory. The raw
material and parsed input stay in the original Read's baseline. The same
normalization continuation grows before audit construction, then the original
measuring emitter supplies the saved evidence parser/comparison bounds before
those constructors enter. Saved parse/hash/encode/comparison work is charged
separately from observed audit work. These quantities are DATA; current Resource
admission, policy and failure custody remain with the same Request.

Authoring uses the exact admitted source retained by that inverse, including
its grammar-owned annotations. The existing authoring collection, path, Writer,
measurement, publication and work continuation are shared with warm preparation;
only the existing reservation's output type differs. Both partial and completed
originals occupy the Request's existing normalization/authoring slots. Failure
keeps the original parent and previously acquired prefix for its existing abort
and retirement, without a refund, physical ACK or second cleanup engine.

The fixed Node caller passes the same parent/input into the typed material
constructor. Its returned pair carries actual materials and the authoring
preparation belonging to that same restored Prepared value. Runtime/Local views
forward this opaque original unchanged; equal CIDs, a copied context or freshly
sealed empty evidence cannot replace it. The extra fixed returned-pair/context
container is included before the constructor. Independent Model/Source reads,
permission, current checks and physical cleanup remain mandatory.

An absent legacy journal stays absent, and existing compiled-material admission
is not replaced with a blanket refusal. Completed Saved reads remain independent
of new publication. A legacy unpublished Run needs its own original facts or a
supported original profile; absence is neither an empty-journal witness nor
permission to reexecute an external action.

The warm installed journal capture also enters the same Request through
`issue_request_model_run_materials`. Its original compiler, checked Program and
retained Parameter cursor determine the projection. Every original Program,
Parameter, Environment, execution inventory and complete material writer passes
the existing body-admission callback before allocation. Retained bodies add;
sequential scratch uses a peak, including the active inventory writer during a
nested execution projection. The shared private admission loop preserves the
Effect family's original-binding/current/failure fences and phase restoration.
The normal Node caller requires this typed Request port; the standalone wire
codec is not its fallback. It issues no replacement checker, graph, journal or
Run. Partial output and the existing compiler remain on the same Request's
original retirement duty.

Warm and cold audit admission share `request_original_normalization_audit_extent_cost`.
It borrows cached original Source nodes/text and the original sequence fold's
visited work, projection-name and authored-expression dimensions. The audit
walks these Program/producer/expression/Source occurrences; it does not copy the
unrelated admitted environment catalogue or allocate at its global carrier
width/name maxima. Those semantic-check estimates stay with their original
checker. Source completion path/escaping frames, original audit entries and
publication writer/hash/failed-child overlap keep their existing construction
laws and separate live reservations. This changes neither the compiler's
work/codec policy nor the Request's capacity ceilings.
