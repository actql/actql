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
