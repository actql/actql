# Physical holding metadata publication

## Original ownership retirement

The existing Store ownership handle remembers successful owner-record unlink
and ownership-directory removal separately from final root durability. An
error after one acknowledged phase cannot force a retry to reconstruct that
record or repeat its deletion. Once the original directory was removed, only
root durability remains; a legitimate successor's owner record is not read or
modified by the predecessor's retry. The original key stays held until the
whole original release returns success.

Root device/inode are observed before acquiring ownership. During original
retirement the handle pins ownership-directory device/inode before removal;
retries refuse a replacement directory or root. Initial absence and foreign
token/pid remain refusal, not evidence of retirement. These path checks do not
claim hostile-filesystem race isolation. Unknown syscall outcome is not an
acknowledged phase. Initial acquisition and other directory-FD failed-close
paths remain separate from this retirement boundary.

Two additional phase Booleans and four device/inode scalars remain in the
existing handle, overlapping temporary Stats objects, read/parse state and
the existing close Promise/error/key. They are explicit lifetime components,
not a new Owner, lease, byte price or a normal numerical resource profile.

Final root retirement also keeps its original opened directory FD inside that
same ownership handle until close acknowledges success. An explicit false or
rejected close leaves the Store unclosed and its private key held. After a
successful sync, the next single-flight Store close retries only the original
FD close, without opening or syncing another directory or touching a successor
owner. If sync itself failed, its original failure and any close failure remain
distinct; only after that FD closes may original-root durability be attempted
again. The acquired FD's device/inode is checked against the original root.
An already-owned pending FD drains before pathname-dependent refusal, even
after the original root is renamed or replaced. The foreign/missing-root
refusal still keeps the Store unclosed and its key held; no replacement open,
sync or ownership operation is allowed without the original root check.

One nullable FD reference and one acknowledged-sync Boolean extend the existing
handle. The transient FD Stats, sync-failure flag/reference, close cause and
diagnostic wrapper overlap the existing close Promise, ownership phases and
key. Native directory lifetime remains the selected Host responsibility;
managed references and pending cleanup are not free or numerically funded by
these filesystem tests. This does not generalize retirement ACKs to other
directory readers or publication paths.

## Original opening directory custody

Directory durability during initial format and ownership acquisition keeps its
original opened FD through false or rejected close. The failure exports the
same close-only, single-flight cleanup facade, without reopening the pathname
or repeating sync. If sync also failed, the raw primary (including null or
undefined) and the close cause remain distinct. Diagnostic attachment defines
own data properties when safe; frozen/readonly errors or a preexisting cleanup
facet remain original causes of a wrapper, never overwritten responsibilities.

The existing ownership release closure is constructed immediately after the
original token is written and before either ownership-directory or root sync
is awaited. The existing opening-failure receiver drains the failed FD first,
then retires that same ownership. Its copied private key remains live until
both acknowledge cleanup. A format-root failure before ownership uses that
same receiver without inventing an owner token. The caller must still retain
the failed initialization carrier; this is not a new global opening registry
or a claim that all publication callers consume every directory-sync failure.
Missing/foreign roots and original ownership validation remain refusals.

The FD reference, sync-failure flag/raw value, original close cause, status and
retry closures, single pending flight, descriptor workspace and optional
wrapper overlap the existing opening configuration/key and ownership record.
Native directory adapter lifetime remains selected trusted Host responsibility;
none of these managed references or pending duties is zero-priced, a new lease
or a normal Model four-role numerical supplier. Cleanup acknowledgement is not
Store initialization success, durability replay, Provider permission or send.

## Bounded metadata reader close acknowledgement

The existing bounded metadata reader does not publish bytes or invoke its FD
retirement callback after an explicit false close. Its existing cleanup facade
keeps the same native handle and callback through rejected or false close-only
retries, without reopening the pathname or repeating a read. Only successful
original close clears the reference and acknowledges that same reader duty.
The ordinary mutable primary failure is retained where diagnostics can safely
be attached; readonly diagnostic fields use a fresh wrapper with the original
failure as its cause. Field inspection or attachment must not mask that failure
or discard the cleanup facade. Existing frozen status snapshots stay unchanged.

The three-name descriptor-check Array, temporary property descriptors and an
optional error wrapper/cause can overlap the original error, raw metadata,
callback and pending retry Promise. Their finite reference count is not a byte
price or a bound on arbitrary Error graphs. The original read reservation and
Store reader count remain responsible until actual acknowledgement; no new
grant, reservation, Owner or normal numerical profile is supplied here.

## Existing atomic metadata publication

Physical holding creation, sharing and deletion intent use the existing Store's
staging directory and exclusive hard-link publication. The complete original
record is written, file-synced and closed before it receives a final name.
The original containing-directory durability acknowledgement remains separate;
visibility alone never adopts prepared custody or confirms an unknown commit.
Existing record bytes, CIDs, conflict comparison and reclamation rules remain
unchanged. Incomplete bytes occupy only an unpublished `object-<UUID>` staging
alias, which the same Store's existing restart recovery removes. A crash after
the exclusive link leaves complete final bytes, not a new commit receipt.

This does not repair a corrupt final record. Each selected holding read admits
its bounded body against the exact requested holding CID before using it;
unrelated immutable records are not all read at ordinary startup. Required
pending-deletion recovery still reads its own original records and refuses
invalid identity or bytes. No missing/empty record is interpreted as an
unapplied operation, permission or cleanup success. Physical capacity accounting,
other Store recovery and their actual acknowledgement duties are unchanged;
this does not make all remaining opening inventories history-independent.

Committed publication owner links are also selected-use facts. Ordinary open
does not enumerate and admit every committed Index merely to check all of its
inventories and holdings. Index inspect, public durable confirmation, lookup,
and Result Binding selection read the selected inventory and require its exact
Index CID, namespace, authority scope, Run and publication attempt. Only that
inventory's holding links are read; missing, retiring, malformed or foreign
owners refuse the selected operation. A later operation acquires new originals.
Already inspected Pure/Effect evidence reuses its own holding facts when joining
the same inventory rather than reading the same bodies again in a pure helper.

During one serialized Index commit, a newly written semantic body may also
retain its private bytes and digest in that commit's existing observation map.
This observation is published only after the original file sync and close,
both new physical and semantic links, their actual directory acknowledgements,
and writer cleanup succeed. Its metadata inventory consumes that same original
without reopening and hashing it immediately. Existing objects or aliases,
including names left by an interrupted attempt, still use the actual semantic
reader and its hard-link validation. Failed durability never publishes this
observation or retires the pending writer. The map is operation-local and its
bytes never escape; the next public read acquires its own original and detects
a changed or replacement alias. No permission, claim or physical ACK is cached.

Internal index durability reconciliation remains separate from public selected
use. It still confirms the real directory acknowledgement and original custody
outcome, including before metadata has been fully staged or during retirement.
This is not a durable ACK or permission cache. Pending deletion, prepared custody,
and quota accounting retain their original responsibilities. Payload accounting
and shared-reference discovery still walk history; indexed publication recovery
does not establish history-independent Store startup or replace an explicit
integrity inspection.

### Indexed pending publication recovery

The existing Store database retains only unfinished publication inventory
originals in its private recovery index. Before acquiring an inventory file,
the Store stages its exact Index CID and bounded inventory wire in a real native
transaction. An existing file representation retains its own write, close and
directory acknowledgements. The pending row is removed only after the original Index
directory acknowledgement and schema adoption. At that point the same Store may
retain the exact bounded completion original and include its removal in the next
already-required transaction of this database. Retention is not a durable ACK:
the original pending row remains until actual COMMIT, and an interrupted process
uses the existing targeted pending recovery. If no later transaction occurs,
close performs the real completion write; an existing physical-quota seal can
include it without a second transaction. Native close remains a separate duty.
These transitions do not replace file acknowledgements or establish a minimum
barrier count. Strict recovery completion remains immediately durable.
The retained map is bounded by the existing pending-entry and wire limits; it
keeps immutable originals, not permission or a new byte allowance. Successful
COMMIT retires exactly those originals. Lost replies retain them for the same
mutation or close retry, and actual native close releases their managed aliases
without claiming an unrelated uncertain mutation succeeded.

An older private database format permits one bounded inventory migration. The
Store confirms each selected Index's actual directory durability, retains only
unfinished originals, and commits coverage with the pending rows atomically.
Subsequent opens read pending rows rather than enumerating committed inventories
or Indexes. Missing adopted tables, coverage or malformed selected originals
refuse; they never rebuild coverage from absence or recreate authority.

A lost native reply retains the same mutation kind, CID and inventory wire.
Only a real same-original confirmation write settles that Unknown; observing a
row is not its acknowledgement. An unfinished publication may restore only its
retained inventory bytes, not dispatch or replay a Run. Once a durable metadata
deletion marker owns the same complete inventory, recovery transfers the pending
original to that marker before physical retirement and never reconstructs its
already removed file. Failed transfer or physical cleanup retains the original
retry duty; no quota refund, permission or cleanup success follows from a callback.

Inventory staging precedes the public Index commit's payload-custody owner.
If its native COMMIT reply is lost, the Store therefore retains that exact
staging original in its existing pending-writer collection and returns its
storage-only, single-flight finalizer with the original Unknown failure. The
finalizer calls the captured same native method and receiver with the same
inventory; it neither selects a replacement mutation nor treats a visible row
as an ACK. Concurrent finalization shares one attempt. An unresolved original
continues to block native reads and Store retirement; close may drain this same
writer but cannot erase its duty. A successful confirmation retires only that
staging acknowledgement, not the Index or Run publication. The next commit
still performs its normal current, evidence, ownership and Index transition.
Legacy file-backed staging retains the same protocol and separate file ACKs.

New inventory bodies are durable originals in that same native staging
transaction, not duplicate filesystem preparations. Completion removes only the
pending lookup; the exact bounded inventory wire remains available to selected
reads. The existing Index file and its actual directory acknowledgement still
determine publication. Stage and completion remain distinct logical transitions;
storing the body with its pending lookup removes the redundant inventory-file
write/sync/close and directory sync, not those logical transitions or payload ACKs.

Private native-inventory count and wire bounds are enforced before insertion.
Additive format adoption creates their tables and count atomically; adopted
missing tables or invalid count refuse without resetting originals. Prior
file inventories remain files and use the same selected-use checks. They are
not copied into a second representation during ordinary open. Retirement binds
the same complete durable deletion marker before removing the native original
and its pending lookup together. Same-original Unknown confirmation is retained.
Shared contract and holding cleanup checks both representations before reclaim;
this does not eliminate the remaining shared-reference history work.

### Indexed Run metadata retirement

The same private database keeps a minimal retirement fence keyed by the complete
metadata key, with an index over the original Run CID. Delivery and publication
operations select that Run alone; they do not enumerate or parse other retired
Runs. The fence denies the whole Run as before, independently of namespace or
Result permission. It is not authorization, capacity or a physical cleanup ACK.

A full deletion marker remains the original pending physical cleanup inventory.
After its actual file and directory ACK, its native fence is staged in the same
transaction that transfers the native publication inventory. A same-lifetime
intent conservatively hides that Run before the transfer ACK. A lost native
reply retains the exact original inventory and fence for confirmation before
other native reads; a legacy file inventory may transfer without a native body.

Only after the original cleanup completes does the native fence record retirement.
The full marker is then unlinked and its directory really acknowledged. A failed
final ACK retains the same cleanup even if the marker is absent and the native
row is already retired. Retry does not manufacture success from either fact.
Completed fences retain only metadata key, Run and retirement state, not the
deleted metadata bodies. They do not permit re-creation of that Run.

An additive format transition reads prior full and compact marker files once,
in bounded native batches. Durable coverage is completed before redundant compact
files are removed. Interrupted migration resumes the same tuples idempotently;
missing adopted tables or incomplete coverage never mean not-found. Subsequent
opens recover pending physical markers only. Other quota and shared-reference
history work remains separate; this is not fully history-independent startup.

## Same-owner cleanup and inventory

A scoped Result reader retires only after both its use callback ends and its
actual consuming FD closes. The existing consume operation's original close
notification cuts that same generation-reader reference. Failed close leaves
the existing cleanup handle responsible, even after the caller receives an
error; Store close and Result deletion remain blocked by the retained reader.
Retry closes the same FD without reopening, rereading or repeating a sink.
No-consume completion and failure before FD acquisition release only their
scope reference; a successful sibling reader cannot retire this duty twice.

The existing Store retains each active metadata writer's record in its private
writer set before opening its staging FD. Holding publication keeps its existing
exclusive writer-admission fence. A false or rejected close keeps that exact FD and forbids final
publication or staging unlink; retry only closes/unlinks/syncs the original
staging alias, never rewrites bytes or creates a new holding. Cleanup is
single-flight, and `Store.close` retains/drains the same duty even if the
caller sanitized or discarded its error. Original prepared-object custody and
the holding-directory ACK remain independent. No key, ownership or capacity
is released merely because a callback returned or cancellation was requested.
After confirmed cleanup, an escaped cleanup handle drops its explicit original
Store/writer association; its retired status does not retain that live set.

Prepared-schema restart recovery first selects its pending marker names. An
empty set performs no contracts/objects directory acknowledgement: it has no
schema transition to confirm. A nonempty set retains the original directory
acknowledgements before recovering its exact markers and physical allocations.
Selected reads and subsequent writes retain their own integrity and real ACKs.

An existing schema preparation retains the device/inode scalars already checked
by its actual semantic reader against the digest object's hard link and extent.
It joins those same-operation facts to the existing prepared-schema generation
instead of immediately repeating both pathname observations. Only this reader
requests the extra frozen generation pair; ordinary contract reads do not retain
another generation object. The reader still hashes its actual bytes, compares
the requested schema and closes its original FD before returning. A later
preparation reacquires its own reader, and a changed retained generation refuses.
New or pending writers keep their final alias observations and real durability
and cleanup duties; the reuse supplies neither capacity nor an ACK.

The original metadata envelope includes the admitted record/Buffer, temporary
path/UUID Strings, file and hard-link/directory operations, writer-set entry,
closure/status/cleanup record, pending Promise/flight, retained original FD and
failure/cause references. The original prepared payload and commit queue may
overlap all of these. A successful unlink is not its directory sync, and a
weak reference or GC opportunity is not a physical acknowledgement. This
inventory is not a byte grant or a normal four-role Model profile; unknown
layout/bootstrap costs remain unknown, and existing limits do not increase.

## Selected Result metadata read reuse

Committed Result retention-extension histories are selected-use facts. Ordinary
open does not enumerate their Run/Result directories, inspect every record name
or acknowledge every historical Result directory. The selected reader checks
both directory types without following a substituted symlink, retains its real
Result-directory acknowledgement, and validates the complete ordered extension
chain and exact Result/Index/base-policy bindings. Missing history still means
no extension; malformed selected history refuses, rather than renewing a policy.
Unrelated committed corruption is not a new opening admission boundary.

Append-only CAS, new-directory durability and deletion/restart cleanup retain
their existing transitions. The retention root's existing opening ACK remains
separate; it is not a per-history acknowledgement or a minimum barrier allowance.
This localization does not remove payload quota or other recovery history work.
### Trusted clock write observation

A warm fixed-length clock update consumes its already typed observation after
the same original file completes write, sync and close. Post-sync FD state and
post-close path state must agree in device, inode, size, modification and change
time. A changed original refuses; a failed close retains the original writer
and retry. The successful write is not reopened, parsed or hashed as a second
wire input. The retained observation is private and immutable.

Each later operation still checks the current physical version; changed bytes
receive ordinary bounded checksum/time admission. Confirmed-floor loss,
rollback, corrupt replacement and unknown durability remain refusal. No write,
sync, close or cold directory acknowledgement is omitted. The no-write flush
and cold/legacy replacement protocol retain their existing post-ACK read; this
optimization introduces no new cold confirmation filesystem operations.

A Result description selects its committed Index and exact Result Binding once.
The description, binding inventory and retention-extension lookup consume those
same admitted values; a private helper is not another authorization or semantic
boundary. The Index's immutable semantic alias still receives its original
bounded FD, inode and digest checks, but byte-identical canonical wire reuses
the Index admission. A different spelling follows ordinary contract admission.

The payload reader also consumes the parsed Binding returned by its original
contract read. Selection and the physical verifier reuse that same private body
instead of interpreting the wire again. It never comes from an external caller
or persists across operations. Other verifier callers retain their own parsing;
actual payload digest/size and schema checks remain, including after a later
operation observes changed physical bytes. Contract-control admission is separate
from this direct Store DATA interpretation count.

Cold commit confirmation retains the bounded Index bytes across the real
containing-directory ACK. It checks metadata retirement again and rereads the
selected Index: identical bytes reuse that operation's admitted value, while
changed bytes receive normal admission and identity comparison. This does not
substitute visibility for a durable ACK or change unknown-commit recovery.

These values and the bounded original buffer belong only to the active read.
No successful admission or permission is cached across public calls. A later
read acquires its own original and observes changed or deleted metadata. All
original FD close duties remain under the same Store, including partial failure.
Payload deletion still permits retained descriptions; metadata retirement does
not. This does not relax Account, Run-read or named-Result-read authorization.

## Delivery admission durability batches

The existing delivery-admission queue admits its grant and attempt once before
writing their immutable originals. The same Store's direct semantic batch
file-syncs and closes each payload before linking either final object. Both
objects share an objects-directory acknowledgement; both semantic hard links
then share a contracts-directory acknowledgement. No prepared holder escapes
between these writes and publication, so this path does not persist separate
prepared-custody records or their later deletion.

The same Store first durably claims the complete logical delivery key and its
grant use; only after this bounded batch succeeds is that claim ready for the
delivery caller. Failure preserves the original cause and a
single-flight cleanup of the same allocations and any failed writer. Cleanup
observes a possibly completed original link and confirms its containing
directory without resealing, allocating a replacement or repeating delivery.
An independently removed unpublished first staging file does not acknowledge a
second writer's still-open FD. The original use quota,
append-only records, commit uncertainty and separate physical-close duties
remain unchanged. This changes transaction granularity, not wire identities,
permission or the meaning of a durability acknowledgement.

Direct semantic writes use the same protocol for a single immutable metadata
contract. Payload data, final object names and final semantic names have real
durability acknowledgements before success. Transient staging aliases do not
establish committed state: their native FDs close before unlink, and existing
exclusive opening recovery removes any such alias resurrected by a crash.
Prepared-object/Content holders still use their separate original custody
protocol; they are not converted to direct semantic writes.

## Joint delivery start

The existing delivery issuer can retain the exact immutable Index, Manifest,
Grant, Attempt, request and limits used for issuance. The Node facade supplies
the same nominal capture/read operation as the packaged Run Host. A copied
view, equal-CID admission or another facade's original does not acquire that
custody. These facts are not an authorization or a capacity original.

When the Store supports joint start and the caller has that original, the
existing delivery queue commits the logical key, grant use, exact Grant and
Attempt wires and initial streaming record together in the same Store SQLite
transaction. That committed database is the durable original of these metadata
bodies; joint start does not also create three contract files and aliases.
The actual native COMMIT acknowledgement precedes row exposure. First selected
reads still admit each exact immutable wire and verify its CID and original
tuple. Wire identities, grant uniqueness and use quotas are unchanged.

A lost COMMIT reply remains Unknown and never refunds a use or authorizes
another stream. A later Store observes only the selected original claim; its
retained streaming record remains unresolved, not permission to resend.
The native index bounds entry count and all three wire extents. Ordinary
payload data and file-backed subsequent records retain their real file ACKs.
The first file-backed subsequent record creates its actual alias directory and confirms
its parent before publishing that record; a visible mkdir does not acknowledge
a failed parent sync. The optional function is captured before callbacks.
Stores or issuers without this connection retain separate create/append and
their actual writer/close duties.

Metadata retirement validates only the selected Run's native bodies and removes
them through the same indexed Run deletion transaction. Its physical-file
inventory contains only real independently present files, never synthetic
object identities or ACKs for SQLite rows. Retirement needs no temporary shadow
files or spare object-file quota merely to remove native metadata. Existing
deletion intent, idempotent Unknown recovery and actual native close remain.

## Joint delivery completion

After the sink finishes and the existing receipt authorization succeeds, the
delivery caller may pass its same-owner issued attempt, receipt and succeeded
record to the Store's optional joint completion operation. The existing Common
success predicate checks those nominal originals before acquisition or writing;
matching shapes or CIDs alone cannot supply them. The selected stored attempt
is still read. An identical wire reuses its issued input; a changed spelling
receives ordinary admission and binding checks. The stored predecessor and
transition remain separate actual observations.

The receipt and record keep their original wire/CID meanings. For a native
joint START followed by its sequence-one succeeded record, the same SQLite
transaction stores both immutable bodies and identities, checks the exact
initial predecessor and owns completion uniqueness. Its real FULL COMMIT
acknowledges this metadata transition; duplicate semantic files, aliases and
their directory ACKs are not required. The completion row is bounded one per
existing attempt, and the same grant use is neither repeated nor refunded.
Actual Result payload files and native/FD cleanup are unchanged.

Legacy file-backed attempts and other transitions retain the semantic writer:
each real payload FD file-syncs and closes before final object acknowledgement.
The receipt and record share one objects-directory ACK and one contracts-directory
ACK, then the record alias requires its actual attempt-directory ACK. No prepared
holder escapes and no intermediate custody file is introduced.

The existing pending-record carrier retains the captured completion function,
its original receiver and all three nominal inputs. A partial semantic writer's
same cleanup child must acknowledge its real pending FD/directory duties before
the carrier retries that same metadata completion. A lost final ACK reply stays
pending even when succeeded bytes are visible. Native completion retains the
same exact nominal inputs; a lost COMMIT reply can retry only that same physical
completion on the usable original connection. An already visible row is not its
missing ACK: retry performs a real revision write and COMMIT. Retry never invokes the sink,
reissues a receipt, claims another attempt or refunds a use. Stores without the
optional operation retain the separate receipt/record protocol; an explicitly
malformed operation is not treated as omission.

The group overlaps two bounded metadata buffers/Strings, reservations and
original writer/FD/ACK state. Existing object count, per-object wire and aggregate
Store limits apply; failure retains original custody and does not guarantee
allocation success. This is logical durability batching, not a new permission,
capacity, storage Owner, wire version or Result/Account authorization rule.

## Indexed delivery claims and coverage

The exclusively owned Store keeps private SQLite lookup metadata beside its
existing immutable contracts and attempt directories. The seven-part logical
key includes namespace, authority scope, Run, principal, purpose, Result name
and attempt ID. A transaction claims that complete unique key and updates the
indexed grant-use counter together. These are the existing Store's lookup,
quota and recovery metadata, not another authorization evaluator or Ledger.
The public caller still supplies admitted grant and attempt originals. A
lookup validates the selected original attempt, its referenced grant and the
index correspondence; unrelated history is neither read nor re-admitted.

A durable building/ready marker distinguishes migration from ready coverage.
The bounded legacy migration reads each original attempt and referenced grant,
refuses ambiguous keys or excess uses, and commits complete coverage once.
Its attempt and grant readers explicitly acquire their original legacy files;
they do not query the incomplete native index or interpret it as absence. The
same bounded admission, semantic digest/hard-link and original reader-close
duties remain. Ordinary native readers still require complete coverage, and
ready or missing adopted state cannot enter this building-only reader path.
Ready opens read only legacy pending indexed claims, not historical delivery
names or grant bodies. A missing adopted database refuses, rather than returning
false absence. A legacy pending claim retains its exact attempt/grant wires and
use quota; recovery installs those same immutable originals and their final
directory acknowledgements before marking the row ready. Joint START claims
retain the initial streaming wire in that same claim transaction. Their
new native representation also indexes the initial CID; older null-CID rows
retain their original file-backed recovery protocol. The additive upgrade does
not scan or parse their historical wires. A new Store reads only the requested
native START, without reconstructing redundant aliases. Legacy preparation
failure or reentry remains unresolved; file visibility does not substitute for
an actual required ACK.
The additive private index upgrade records its version transactionally; a
missing adopted initial-record table refuses rather than recreating coverage.
This is private lookup metadata, not a public wire or contract-version change.
Recovery never dispatches payload,
replaces an unknown business attempt or refunds a failed preparation. Pending
staging aliases are derived from that same attempt, so recovery locates them
without another global directory enumeration. Metadata retirement removes the
same indexed Run rows only after the original delivery directories retire.

The native database uses WAL, FULL synchronization, fullfsync and checkpoint
fullfsync. A failed COMMIT is unknown even when the connection has left its
transaction; unrelated work refuses. Only the retained same-original physical
finalization may retry as specified here, or close/reopen observes the durable
original state. Bounded input/row counts are not capacity or permission.
The original native wrapper and captured close/isOpen remain owned until real
close. Store exclusion and key retirement follow that ACK and all independent
payload or directory-FD ACKs, including partial opening failure. Cancellation,
GC, a marker write or a successful sibling close is not their substitute.
An unknown indexed retirement may retry only the same Run's idempotent
metadata removal on a still-usable original connection. It counts only rows
still present, so an already committed removal cannot decrement twice. Claims,
another Run's removal and delivery remain refused during that uncertainty.
An unusable connection is never treated as a successful cleanup.

This metadata index does not change grant/attempt/record wires, authorization,
Result binding, append transitions, stored public formats or optional delivery
capabilities. The separate public operation still observes current policy.

### Publication metadata in the same database

The Store also retains new publication metadata groups in this same database,
instead of separately synchronizing duplicate body files and aliases. Existing
file originals, Index/schema and file-backed attempt/progress protocols remain
supported. The native group owns one real durable transaction, not a provisional
per-body ACK. The existing Store's byte/object limits include native bodies and
unresolved reservations beside actual file objects. A persisted usage singleton
changes atomically with those bodies; ordinary open does not enumerate them.

The private inventory identifies native semantic bodies by their complete-body
digest and byte count, not a fabricated physical-file identity. Shared inventory
references retain the same row. Last-reference removal changes the row and usage
in one transaction. A lost reply keeps the same exact put/removal duty; only a
real same-database confirmation write settles it, never a visible row or another
Run's operation. Missing adopted storage/counters refuse without reinitializing
capacity. Payload and original database close ACKs remain separate.

The additive completion layout also retains explicit confirmation of an initial
native record, including after a terminal successor. The same Store reuses its
successful original claim/completion ACK. A fresh Store's first explicit record
confirmation performs a real bounded revision update and COMMIT in that same
database; unchanged subsequent confirmations reuse only that lifetime's last
confirmed identity after checking the selected original wire. A failed reply
retains the same original confirmation and fences other work until its own
physical retry succeeds or the native connection closes. No read-only transaction,
file visibility or fabricated directory ACK substitutes for that outcome.
Missing adopted completion metadata refuses; upgrade does not parse historical
bodies. Same-Run retirement validates retained typed receipt/record bindings and
removes their rows through the original indexed deletion transaction, preserving
other Runs and real physical-file duties.
Focused history, quota, migration, ambiguity, COMMIT-loss and native cleanup
cases exercise the existing Store boundary; they do not establish ordinary
package latency or close other startup/retention inventory costs.

If an object link completed before a failed reply, its actual inode is observed
without repeating the write. A completed immutable object remains charged to
the existing Store inventory even if its semantic publication failed. Recovery
and an explicit same-wire retry can reuse it; neither an error nor a crash
refunds it or issues new authority. A pending final-name acknowledgement stays
under the same Store writer duty, and Store close cannot release ownership
before its original native and directory duties finish. Buffers, pending
directory names and original reservations are bounded by the one or two input
contracts and the Store's existing limits, not an additional capacity grant.

## Delivery record operation reuse

An append admits its input record once and retains the same original attempt
through transition and success checks. Its private semantic write consumes
that admitted wire, rather than entering public admission again. An unchanged
latest record reuses the input only after exact wire comparison inside this
operation; the public latest-record reader cannot supply this private handoff.

The original containing-directory ACK still precedes confirmation. The same
record is reread after that ACK and compared with retained canonical bytes,
without another parse or identity hash. A distinct valid wire spelling retains
its existing admission fallback; an identical reread reuses that result. Changed
record identity or content, missing records, transition conflicts and unknown
durability remain refusals. A later public append or confirmation admits its
own input; no admitted-record or authorization cache persists across calls.

The Store keeps at most one last-confirmed record CID as a durability
observation. It is set only after the real containing-directory ACK and the
post-ACK selected-record check. Reconfirmation of that immutable record still
admits its input and reads/checks the selected file, but does not repeat the
already successful directory ACK. A newly installed record, a different CID or
a fresh Store needs its own ACK; a failed ACK or changed record cannot populate
this observation. This bounded String does not retain an admitted contract,
policy decision, payload, native handle or history inventory. Existing record
immutability and the same exclusive Store ownership remain required.

The operation retains one bounded record buffer and the admitted input/attempt
references until confirmation. Existing native FD close, payload/custody and
directory durability responsibilities are unchanged. This removes repeated
contract work, not any required durable write or acknowledgement.

## Prepared-object custody records

### Indexed physical object usage

The same exclusively owned Store database retains derived physical object
usage: content CID, byte count and the actual device/inode generation, plus
aggregate object/byte totals and completed migration coverage. This is private
quota metadata, not another storage authority, Account grant or physical ACK.
The physical-usage stage of clean ordinary opening reads the aggregate and only
legacy pending preparations; it does not enumerate every committed payload to
reconstruct capacity. A bounded one-time
legacy census completes atomically with its totals. Missing adopted tables or
the aggregate row refuse rather than resetting or rebuilding coverage.

Every possible new final object has recovery coverage before link. Tracked
and untracked byte writers retain the existing internal prepared-custody record
until installation accounting or original cleanup settles; untracked callers
do not receive another public capability. In the legacy direct index mode, a
semantic batch retains its bounded generation originals in the same native
database before linking. Its real object-directory ACK precedes the transaction that records installed
usage and removes those pending originals together. No per-item custody file
or custody-directory ACK is introduced by that batch.

Legacy pending-only cold recovery observes the selected original generations. An
installed generation is charged after the real directory ACK; an absent or
different generation only retires that pending preparation, never a successor's
installed charge. Immutable objects left by an interrupted semantic publication
remain charged even when no semantic alias was published. The existing staging
cleanup is separate from final-name and native transaction acknowledgement.

Unlink and its containing-directory ACK precede decrementing the same physical
generation. Lost native COMMIT replies retain the original rows and cleanup
until a real same-original idempotent transaction confirms the outcome. Reads,
visible absence and process exit cannot provide that confirmation. A failed
ACK keeps the charge and pending owner; retries do not relink, resend, substitute
an inode or decrement twice. Schema recovery likewise settles its retained
generation after an interruption between unlink and directory acknowledgement.

### Owned physical quota lifetime

The exclusively owned ordinary Store records a real durable dirty mark before
its first final-object installation or unlink, not at read-only open. The
previously unused `user_version` header of this private SQLite database is zero
for a sealed quota snapshot and one for an unsealed owned lifetime. Other values
refuse; missing adopted physical tables or usage still refuse. This header is
derived quota recovery metadata, never Account, Run, authority or a file ACK.

After that ACK, the same index retains bounded quota changes and preparation
generations in memory. Payload sync/close, object/alias directory ACKs and all
physical cleanup still occur before their existing success boundaries. A failed
unlink ACK keeps its original generation charged; a same-CID successor can be
charged separately without replacing that retiring original. Only its own real
ACK decrements the old charge. The current physical count bounds live and
retiring generations. The delta retains at most the old indexed generations
plus the current bounded generations, not an operation history or Allow cache.

Safe Store close seals those exact deltas and usage totals atomically with a
clean header in one FULL/fullfsync transaction. Selected old/current generations
and totals are compared within that transaction. Lost COMMIT replies retain the
same immutable seal, forbid new work and retry only that original transition.
The seal does not replace the original native close ACK; once sealed, failed
native close retries only that close. An unrelated unknown mutation or unusable
connection may physically close without claiming a clean seal, retaining the
unclean recovery marker and original uncertain outcome.

Only an actually unsealed prior lifetime permits bounded physical extent
recovery under the same Store exclusion. Recovery checks names, file types,
extents and actual configured capacity, then atomically replaces derived quota
rows and clears the dirty header. It does not parse or authorize historical
Runs, repair missing adopted metadata, replay execution or grant fresh quota
from a missing record. An interrupted recovery remains unsealed or atomically
sealed. Later clean opens use the indexed snapshot without repeating a census.
Read-only opening, selected reads and close do not start or seal this lifetime.

The existing Store limits bound installed totals, pending generation rows,
selected metadata, active reservations and cleanup. Native metadata transactions
and byte-writer custody persistence remain real costs; they are not asserted
minimum barriers or evidence of public-operation latency.

Original prepared-object custody now uses this same Store-owned metadata
writer: only a complete, file-synced and closed record receives its exclusive
final `prepared-custody/<UUID>.json` name. The original custody directory still
needs its separate durability acknowledgement before the object writer links
its payload. Record bytes, recorded payload device/inode, custody/reclamation
identity and recovery validation are unchanged. Empty or partial bytes from an
interrupted write remain in the existing staging namespace, where original
restart recovery already reclaims unpublished aliases. A corrupt final record
from an older process remains refused, not repaired or treated as absence.

Independent prepared writers retain their existing concurrent behavior; they
do not acquire the holding-publication exclusive fence or a new queue. Their
metadata FDs join the same Store duty set before acquisition. Failed/false close
is retained there even if the object writer's error is discarded; shutdown or
the same single-flight handle performs close-only cleanup. Completion never
reseals or resends a request. The additional staging path, record/Buffer,
writer-set entry, closure/Promise and original error/FD overlap with the payload
writer and reservation until actual retirement. This is explicit inventory,
not numerical funding or a physical-byte exemption.

A failed metadata duty also prevents a new metadata FD acquisition until the
same duty retires. Its payload reservation can already have been returned, so
that reservation's original object limit cannot be reused as evidence that the
failed metadata lifetime ended. The existing writer record adds one private
failure Boolean; admission scans the existing duty set without copying it.
Healthy in-flight metadata writes do not activate this fence and may proceed
in parallel. Retry only retires the original FD/staging duty, without rewriting
the record; after actual retirement ordinary preparation is admitted again.
The Boolean and scan iterator/workspace remain explicit control inventory,
not a new Owner, counter, FD quota, numerical profile or permission grant.

## Verification boundary

The independent tests interrupt the actual filesystem write before any byte
and after eleven bytes in a fresh process. Other cases exercise false/rejected
close, same-FD cleanup, error-discarded Store shutdown and unchanged refusal of
an old corrupt final name. The existing prepared release tests retain lost
commit replies and delayed directory ACKs. Protocol admission uses the explicit
contract-control fixture; these are real Store/filesystem/process tests, not
genuine Core admission, installed Model acceptance, Provider I/O or numerical
funding proof. Original installed failures remain separately source-qualified.
# Bounded-reader diagnostic transfer

The failed metadata reader defines own cleanup data properties rather than
invoking inherited setters on the primary Error. Safe writable own properties
retain their original attributes; readonly/frozen primaries remain the cause of
a fresh diagnostic wrapper. The same FD, retry flight and original retirement
callback are unchanged. Three definition descriptors and the fallback
descriptor object overlap the existing inspection descriptors/control frame;
they are not free storage or a proof of the retained error graph's byte size.

