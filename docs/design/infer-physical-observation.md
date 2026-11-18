# INFER physical diagnostic boundaries

The existing Model execution Owner retains the original durable Entry and
its issued one-shot gate across the `BeforeInvoke` diagnostic callback. That
callback is explicitly **unsent**. Cancellation, deadline, current dispatch
authority, egress and the original reservation are checked again after it.
Only then is the original gate consumed and the fixed invocation entered.
No diagnostic callback, await or request reconstruction occurs between final
consumption and invocation.

`InvokeStarted` reports that the installed invocation entry was crossed. It
does not prove network transmission, provider acceptance, response validity,
capture persistence or Run success. The synchronous interface delivers this
fact after the invocation returns; the subsequent return/failure/cancellation
fact describes that invocation's disposition only. An invocation that throws
or loses its response can leave the already retained durable Entry unresolved;
absence of a start diagnostic does not prove that no send happened. It grants
neither a new gate nor an automatic retry.

Diagnostic delivery timestamps cannot measure the synchronous invocation's
duration. The Node observation consumer therefore omits duration for these
facts. A conforming asynchronous physical adapter may separately measure its
actual boundaries; a missing measurement remains unknown, not zero. The
pre-gate diagnostic is not exported as a completed transport observation.

Both immediate and polled persistence use the same original final gate.
Saved acknowledgement custody is independent of current send permission.
Legacy non-durable calls also recheck their existing current authorities after
the diagnostic callback. No new Run, Ledger, approval or execution Owner is
introduced by these diagnostic boundaries.

## Complete Model groups on one Request

A Pure computation with several checked INFER occurrences retains their full
compiler order through one TaskCompilation, module and Model Plan. Source-free
and captured modules use the same aggregate Plan fold. Compute demand is read
once from the selected module; each actual Model and read partition contributes
once. A Source capture retains the original checked Direct Stage/input/task
coordinates from preparation through acquisition and execution. Occurrence order
is not a substitute for Stage or input coordinates.

Singles and complete groups project configured Local planning demand through
the same offer/search/revision calculation. A group supplies all checked
input/output binding occurrences; the module policy ceiling is not added as
mandatory work. Original per-Model budgets and actual cumulative charges on
the same Ledger remain unchanged, including after retirement.

A native Query Source shared by several Model occurrences keeps its original
Source reference, database/table and admitted protocol bodies on that same
module. The indexed typed component callback retains each original Model input
and suffix; it does not manufacture a Row declaration/provider or parse and
compile an independent Query for each Model.

The existing original read owns a closed group of consumers on one Run binding,
one descriptor, one read claim and the same Ledger. Each original Model Scope
consumes only its declared partition. Work and attempts remain consumed when a
child retires. A refused first admission cannot obtain a replacement claim or
snapshot. The native fixed group records and actual child arrays use the common
representation units; small Host control frames use the existing common control
envelope, independently of JS closure or wrapper spelling.

The first completed original Model retains the one complete publication borrow.
Later Model captures use that same original borrow without changing compiler
order. Observation issuance validates the complete original group. Every child
publication alias and Store duty retires before that borrow returns; every
actual read and Scope retires before the existing Run and Request aliases are
severed. Construction failure and cancellation use this same cleanup sequence.
A pending child, reentry or replaced carrier cannot become parent cleanup ACK.

Stopping the original read consumer prevents new observation issuance and
further evidence work. It does not prevent retirement of already-owned
observation metadata. That retirement still requires the same live original
Model, Scope, publication reservation and mutable Resource fence; a parked or
foreign backing is refused. Retiring the metadata does not return the caller's
publication borrow or acknowledge its remaining Store and alias duties.

A complete group is not a singular Model-state writer. The existing singular
writer refuses a group before consuming its descriptor. Authenticated recovery
and independent saved Result access retain their existing contracts; a fresh
Scope or successful public status is not a physical-stop or recovery receipt.


## Original Model inventory construction

Installed Model definition counts describe the checked graph's selected
component inventory. They do not grant calls, rows, attempts or provider work.
The original Request construction reservation covers the selected component,
Scope and preparation wrappers before the Host receives them. The adopted
Model and Effect Plan retains the corresponding quantity on that same Run.
A supplied count or caller-created getter cannot stand in for this original
admission. Legacy entrances keep their independently bounded inventory.

A completed original operation grows its existing publication borrower before
constructing capture wrappers, exported call arrays or evaluation bundles.
The module-issued inventory receipt binds the exact operation, funding owner,
count and current numerical scope; it carries no new Ledger or authority.
The cached bundle and Model-evidence projection remain DATA on that original
custody and retire with its publication aliases. A larger complete group must
account for every original member in order; an unproved member cannot borrow
a sibling's receipt to bypass the legacy aggregate bound.

Evidence-copy construction uses the same original operation and publication
borrower. Its request geometry, output and already-live material remain
co-held through the copy. A reserve callback, equal wire or arbitrary receipt
is not proof of that funding. Currentness is rechecked before construction and
after the grow, and failed or pending cleanup retains the same original debt.
Stopped-attempt proofs are funded on the original Model state before their
construction; stopping cannot obtain a late publication grant or a new send.
These witnesses remain separate from Store acknowledgement, Result acceptance
and actual physical cleanup.

## Original retained Model input and cold masks

A retained Model input is handed off through the same physical completed input,
Read consumer, compiled Program, Definition and Plan. The materialization witness
is opaque, one-shot and bound to that original input. Its required geometry is
derived internally before construction; a caller-created amount or Ref cannot
supply credit. The receiving constructor span includes the Resource owner's
actual retained prefix and the simultaneous old/new material. Foreign completion,
small original capacity and an unquoted binding remain refusals.

Cold reconstruction borrows that same retained input and completed journal. It
funds the exact boolean mask before reading the lazy slot view or constructing
its map, checks the selected count, and restricts the same original operation.
Cancellation and first close retain the original Read and pending physical duties.
Reconstruction does not reopen Source, replay Model, issue a replacement send or
acknowledge a physical child. Legacy and explicit smaller inventory choices,
including the installed Task's standard item policy, remain binding. Explicit
Core limits can exercise a larger retained inventory without changing that policy.
The named materialization and cold-mask tests are Source contract references;
normal installed and saved acceptance require their own execution evidence.

## Effect Model startup on the original Request

An Effect's Model child retains the same selected provider, Graph, rows and
read consumer on the original Request Ledger. Generated Content inputs enter
the same shared-provider startup as composed inputs; their authentic producer
and generation still pass the existing input/current checks. The child does
not require the whole Effect Ledger to equal its Model-only limits. Instead,
the existing checked startup retains that exact Model limit object and checks
it against the original parent without issuing another Ledger.

Before binding the Model read Scope, the Request configures its selected
installed quantities intersected with the original execution ceiling. Pure
and Effect share the same quantity fold. An identical pending retry observes
the retained configuration; a different configuration or already bound Run
cannot reset consumption, uncertainty or original input work. Model startup
continues to require exact agreement with this pre-read configuration.


The installed recipe keeps its startup controls separate from the complete
Model allowance. Binding a recipe adds native Model capacity to that allowance
for the Plan; it does not turn the whole allowance into a live startup object.
The existing installation association retains the original startup-control
amounts without adding another registry or numerical policy.

The same Effect Plan lends its selected Model limits to the original read
Scope. Before input-capacity handoff, the Model child borrows those limits from
that exact live consumer; a foreign or spent consumer cannot supply them.
Checked input, item/work and request limits remain immutable. Startup controls
and later physical-attempt/output duties are charged separately on the same
original Ledger, within the already quoted total. No cancellation, absence or
unused allowance acknowledges physical cleanup or refunds consumed work.

## Optional usage publication on the original capacity

Optional usage publication continues on the existing Model publication capacity.
The original INFER facade retains the exact Execution and rechecks its claimed
Read before selecting another physical action. A current Model/Scope by itself
is insufficient after that Read has stopped. The facade is a funded reference
carrier, not another Ledger, execution Owner or grant.

Common selects the single outstanding retain, authorize, capture, record or
retire action. A physical observation consumes that exact nominal action and
original facade; stale, foreign and out-of-order observations refuse. The Node
binding snapshots only the Sink's own DATA completion field, executes callbacks
and awaits their actual settlement. It does not independently aggregate usage
availability or select another slot. Token absence stays distinct from zero;
optional failure cannot alter Model completion/Unknown or authorize a resend.

The added optional reference in the publication carrier is charged before the
initial reserve even when it remains None. Existing complete payload quotes and
actual admitted extents are distinct: convert a payload once; never add the
carrier delta to an already absolute extent. The Native pre-open observation
Plan includes this actual extent, and identity-scan headroom subtracts the same
actual fixed base. The initial constructor, grow and release use one reservation
and the original Request ceiling.

The continuation and action/item backing are funded before construction, then
the existing bounded seven-field usage writer grows the same capacity for its
actual output. The adopted call/attempt references used in completion items are
retained before awaiting a callback; a current loss does not trigger another
original read while building an incomplete receipt. A stop request leaves an
outstanding callback owned. Publication release remains pending until its
matching child reports actual local cleanup. Cleanup after Read revocation is
release-only and does not reacquire live read authority.

This is the explicit usage-aware local Sink DATA contract. It is not a new
version of full invocation evidence. Full and typed-input projection retain
their existing paths. The selected implementation exports the Node family;
matching generated Wasm/Python entrances and normal installed acceptance remain
separate obligations, not consequences of this source declaration.
