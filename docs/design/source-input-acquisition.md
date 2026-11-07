# Original Source input acquisition

`sourceview_resolution.SourceAcquisition` selects the original input of a
checked, bounded snapshot Source request before authored computation. It retains
the same `PipelineRequests`, `DirectMode`, `ParameterizedRequest` and checked
pipeline. The source slot is resolved to its actual pipeline input position;
neither a task ordinal nor a later Select output substitutes for that input.
The existing `parameterized_request_wire` encoder emits the same bound literals
and Parameters. Derivation does not re-admit request JSON or fill missing fields.

Downstream Select, Sort, shared consumers and direct Result references do not
change this input boundary. They remain checked operations in the original
Program. In particular, a Sort still needs its existing total-order evidence;
Source derivation cannot infer a key from an `id` spelling. The separate
[Query-shaped acquisition](query-acquisition.md) entry retains its exclusive
scan → Filter → Select rule and capture after Select. No Filter is synthesized
to make a native Program fit that profile.

`run_publication_host.prepare_client_source_acquisition` reads the same Stage
requests from its prepared Program. The Effect entry uses the existing original
Effect-free view. The correspondence checks compare that original request owner
and source occurrence; equal Programs, request wires or contract CIDs cannot
replace them. Work limits cover bounded input-name lookup before construction.
These synchronous projections start no I/O or cleanup lifecycle. Cancellation
and semantic retirement stay with the receiving parent and its physical child.
Changes/checkpoints, unbounded reads, keyed requests and unresolved Host bindings
require their own acquisition paths and are refused by this entry.

This selection grants no physical read, current decision or completed capture.
The receiving Host must retain the original complete input and its actual
observation before downstream computation, under the same admitted parent. Its
whole-input bound is independent of a Query Select-result guard. Constructor,
retained input, output and failed-child overlap, response charges, issuer/current
association and semantic retirement still belong to their existing owners. A
Query receipt or Select completion does not become input evidence by relabeling.

The portable Source tests exercise original parameter binding, unfiltered
Select/Sort, direct/shared input use, unchanged Query exclusivity and exact work
refusal. The prepared Program tests exercise Pure and Effect owner correspondence.
These are typed preparation/component checks, not Account, RowRun, physical
transport, normal reader acceptance or durable recovery evidence.

## Whole input custody and computation

Before Plan construction, the existing Query shape inspector makes a closed
selection from the same Prepared/Request invocation. An exclusive Query retains
that original route, including its separate Query-time binding obligation.
Only a structural non-selection can construct the whole-input Source original;
work, binding, mode and malformed-original failures refuse rather than selecting
another constructor. The original graph still has its original acquisition
prefix during this selection. Only the selected whole-input Plan creates the
physical graph view in which the authored root is pending Compute.

The existing RowRun has a complete-input alternative alongside its Query
alternative. It retains the same checked Program, Source acquisition,
Parameters, installed relation contracts, complete declared schema and bound
sequence. It admits every declared input cell before downstream selection.
The actual received response is charged before decoding, and its original
one-use ticket backs the corresponding admitted page. No synthesized row wire
is charged as another physical response.

Completion of input admission is followed by the existing bounded original
key and score validators. Their cursors and workspace stay on that RowRun;
validation failure or cancellation retains them until cleanup confirms. Work
is cumulative across the original admission and both validators. A capture
cannot issue before the selected transport verifier has settled and all input
obligations have passed. Current callbacks may reenter close, so original state
and correspondence are checked again after each callback.

The input capture borrows the same native row arrays and exact supplied-read
binding. It does not run a residual or copy and readmit rows. Its Input target
is explicitly excluded from pending task completion. The separate input export
requires that same live native read; ordinary Result export keeps its existing
completed-output target restriction. Logical input identity and Source evidence
are issued from the complete captured input. Under the existing weak
read-committed law, its logical input identity supplies the content-derived
observation identity; this does not assert a provider snapshot guarantee or
serialize a Query receipt.

The original Source/Compute Plan retains a complete-input variant. Its checked
physical graph view supplies the exact input to the original root computation;
the authored root remains pending and executes its actual Select, Sort and
other supported operations. Program, Parameters, task coordinates, Result ports
and downstream wiring remain original. The initial supported view is one direct
Source input; native file listings require their different Resource, native
inventory and retained-material recipe and are refused by this JSON lane.

The Plan composes the original input, provider, Compute imports, output and
simultaneous failed-child bounds through existing capacity functions and units.
These immutable capacity DATA reserve nothing. Actual initialization and
Request construction must already hold their own input-sized material before
constructing these objects. The same original Request supplies the Run ledger;
there is no second Ledger or independent cleanup engine. Whole input remains
in its Source holding alongside Compute rather than being mislabeled as the
root's output allocation.

Local managed dispatch distinguishes native supplied reads from imported
producer representations. A supplied read is already admitted and remains
owned by its Source; it constructs no wire importer and incurs no second
wire transfer. Both the retained Plan and actual candidate therefore count
only the inputs that require import storage and transfer. Native input work,
Source retention and output overlap remain in their original reservations;
this distinction neither enlarges a task envelope nor bypasses its check.

The standard installed adapter selects the closed input variant from its
original Plan. It forwards the same acquisition, request wire and provider
response borrow; a missing matched callee refuses. The provider still supplies
only request/cursor/decode logic. Typed Source evidence transfers once from the
same capture. No permission, current decision, physical stop or cleanup ACK
comes from its getters, capacity, logical identity or wire representation.
Retirement invalidates new reads before reclaiming input storage. Pending
validator, provider or physical stop keeps the same reservation and retained
originals for cleanup retry; only confirmed cleanup releases them.

The installed capture opener consumes that same adopted Plan and its live
captures for both Query and whole-input variants. It does not prepare another
sequence configuration from the original Query graph. The Run retains the
opened DAG before configuration can fail. The returned Compute host therefore
uses the Plan's original provider selection, capacity and physical graph.
Source capacity preparation and Plan construction obtain task zero through
the existing prepared full-sequence helper with the same original limits;
neither path lowers a duplicate root sequence outside that retained original.

Dispatch projects acquisition-Result placement from this same adopted Plan's
physical graph. The original Query graph predicate retains its old meaning.
Whole-input dispatch also reuses the Run Ledger through its exact Plan,
capacity and retained Source-read association; a Query-capacity array cannot
stand in for that different typed input. The existing current callback and
post-callback original fences precede returning that same Ledger.

For the existing single direct input in the first stage, an ordinary Pure
Program's checked root Result can still refer to the acquisition prefix even
when its Filter/Select also fits the narrow Query grammar. The original
Prepared/Request selector reads that Result placement before Query lowering
and selects complete input. The same full-sequence Plan then executes the
authored predicate and publishes its actual Task output. A Query prefix whose
root belongs to a later Compute stage keeps its narrow route. Model, Content
and Effect purposes retain their separate constructors.

This is a checked graph choice, never fallback after a Query error or a
caller-supplied purpose flag. The complete-input capacity constructor checks
the same nominal Source original against its Prepared Program, then consumes
its complete sequence and declaration. Reinspecting the narrow Query grammar
there would lose the already selected Result purpose. The original Source
derivation still refuses unbound requests, unsupported read modes and exhausted
work; the actual input/provider/Compute/output overlap remains in the same
existing capacity calculation and Request reservation.

Whole-input publication binds the same adopted Run, Plan, native RowRun capture
and Source acquisition. A receiver-bound private capture view exposes that same
native capture while live; copying its methods or retiring the input cannot
supply another occurrence. The publication owner checks the exact Run association
before issuance and again before retaining the completed invocation. The existing
one-shot invocation slot remains consumed on semantic failure. Complete original
Source evidence and logical input values must fit the caller's encoding bounds;
equal wire representations cannot replace their native capture correspondence.

The original Task compiler represents external inputs even for a single task.
Its Result port follows the same closed acquisition selection: Query publishes
its checked capture port; whole input publishes the actual authored Task output.
The original graph's acquisition prefix is not changed by compilation. The
whole-input Pure Plan also selects its existing checked schema-demand inventory
before capacity construction, so Result-publication reservation reuses that
same retained inventory and admitted row bound. No completed output, numeric
profile substitute, second Ledger or new current decision supplies those inputs.

The JS publication boundary selects from the adopted original Plan, rather than
classifying a copied graph or falling back after an error. Whole input passes
typed Source evidence and the same native capture to its whole-input issuer;
the Query issuer keeps its original QueryRequirement array. Missing originals,
foreign owners and unsupported selections refuse. Invocation DATA do not close
a physical child; the same Run retains its input and pending cleanup until the
original provider/RowRun retirement confirms and the body borrow is returned.

The Host retains the original pure Request identity before acquired-input
preflight and consumes the compiler's closed Query-or-whole-input selection.
Only the Query branch constructs a Query requirement. Actual acquisition passes
that same Request identity to the managed Source adapter, whose existing wrapper
binds the original parent and checks currentness before and after preparation.
An error cannot select another route, and neither the identity cache nor a
selection's reference DATA grants a read or replaces the parent's cleanup.

A native Source profile returns the same Host Run that it has retained and
rechecked. Submission retains that returned original before dispatch selects
the Source's Ledger capacity. Its identity must match the Run retained by the
Source; a scalar quote or a second lookup cannot replace this handoff. This
return carries no additional read grant, preparation or cleanup acknowledgment.

The normal Source service retains the selected reader's node and depth bounds
in the same immutable reader demand as its response and row bounds. Whole-input
capacity construction and RowRun Begin consume that same demand. The legacy
`originalPageLimits` option still requires its original preparer; a managed
provider does not supply a dummy preparer or a second page-limit option. Query
acquisition keeps its existing page selection. These bounds do not reserve
capacity or override the complete same-parent Plan admission.

The focused Core and explicit-port Node cases exercise full input beyond a
Query result bound, original key refusal, callback/current fences, pending
physical close, same-Request adoption and the still-pending Compute root.
They do not establish the ordinary SDK, Account, authenticated transport,
publication, separate-process Saved or final normal-distribution acceptance.

The Node consumer decodes the original whole-input identity's optional Array
through the pinned compiler binding before checking its two CIDs. An absent
identity or malformed pair refuses; it cannot become Query evidence or a new
request identity. Once the managed parent opens a Source read, the Source
retains that same constructor read until the accounted RowRun constructor
returns. Returning a prepared JS value or installing a managed-wrapper
association does not transfer this read. Any earlier failure retires the original read. A pending retirement stays with the same
Source close retry, before Site and constructor-material retirement; returning
a failed preparation does not acknowledge that cleanup or release its parent.
A close that retires this constructor read during an authorization await also
fences its later handoff; resolving the authorization Promise cannot revive it.

## Source observation and Result publication policies

Single-Source dispatch obtains the Result publication policy from the same
checked Program's existing getter. It does not substitute the captured Source's
read policy, compute a new join in JavaScript or reprepare either original.
The actual Source evidence keeps the exact read policy already bound to its
acquisition; its evidence wrapper and native capture remain unchanged when the
publication plan receives the checked Result policy. The common issuer verifies
both distinct obligations. An absent or refused checked publication policy
cannot fall back to a known Source policy or create another invocation.

## Original QueryTime in whole-input construction

Timed whole-input construction consumes the same opaque original invocation
returned by the existing QueryTime owner. It retains the same Prepared, Request,
first compilation and Definition; the Host forwards the original Option without
inspecting or rebuilding its tuple. A missing or foreign invocation refuses
before the selected whole-input constructor runs. The same Request keeps the
construction borrower through Plan and module completion, and the adopted Run
retains that invocation for publication instead of sampling or compiling again.

Original current and retirement fences remain at their existing owners.
Returning a body does not acknowledge physical stop or retire a pending child.
Constructor and held-output overlap must already be backed on the original
parent before allocation, including failed children; the invocation and Plan
limits do not establish that backing. The untimed constructor retains its
existing signature and input semantics.

## Before-call backing for the original timed invocation

The Request retains its first raw compilation before the timed Host callback.
The same parent and input reserve one aggregate invocation extent before that
callback may issue a CompiledRun, Definition or QueryTime. The fixed trusted
control group is prepaid at the original entrance; variable backing follows
the retained artifact geometry and the existing bounded metadata codecs, with
maximum sequential scratch rather than a per-task or per-closure census.
A cached absolute target survives a declined grow without repeating the compiler
or callback. Current reentry is fenced before the original capacity callback.

The existing Host Run bag retains one partial invocation view before entry.
Each returned original is stored before the next issuer can fail. Success freezes
that same lean view; the opaque Core Option is forwarded unchanged to Plan and
Module and is not cached as another retained root. Failure keeps the original
parent, output aliases and occupied extent through existing cleanup. Payload
sever clears the Host view before the consuming parent borrower return; a
settlement throw retries that same parent without restoring heavy aliases.
Original handler and dispatch returns settle the same reservation; returning or throwing does not acknowledge physical stop.
The pre-admission retained Definition parse is bounded before parsing, while
the original native codec limits and original-identity checks remain required.

This invocation extent is not a replacement for Source declaration, physical
reader or output backing, and does not enable Model, Content or Effect purposes.

## Result placement from the adopted Plan

The managed Result-placement read accepts the same live Pure Run, Prepared and
Request. A captured Plan supplies its retained physical graph, whose Result
coordinates may differ from the original Prepared graph. A source-free Plan
supplies the graph of its retained original Pure owner. Missing, foreign or
retired holders cannot select either graph, and an acquisition count cannot
replace the checked root Result inventory.

This immutable read performs no current callback, compiler work, reservation or
provider construction. It does not admit execution, supply physical backing or
acknowledge cleanup. Source-specific input and Ledger reads retain their own
captured-Plan restrictions and existing current boundaries.


## Installed Gmail thread sequence

The installed Gmail THREADS route uses its original Source initialization and
Host reader services. The service retains the selected complete list/get limits
and requests `installed_gmail_thread_reader_capacity` once. Core composes the
existing JSON response, row and failed-response workspace with the actual Gmail
control's retained pages, nominal requests, checked thread values and control
frames using the shared representation tariff. The quote is DATA; only the same
checked acquisition and parent admit that backing before reader construction.
No profile number supplies an original capacity or an authorization.

The existing Gmail protocol is shared by the explicit Credential reader and the
installed managed reader. It consumes a list observation or a complete thread
row before issuing the next nominal request. The Source owner gives each request
its own monotonically consumed occurrence, keeps the original list grant bounded
by list pages and the separate get grant bounded by threads, and checks current
Account/Site state before physical use. Copies and reentrant repeats cannot
restore an already selected occurrence or consumed physical work.

Gmail control closure only retires the protocol graph. The shared reader retains
that graph through pending original consumers and invalid asynchronous provider
callbacks; it then joins protocol retirement with its existing response, physical
binding and original binding-retirement duties. A closed protocol, completed row,
process exit or stopped socket alone is not a physical cleanup acknowledgement.

## Keyed Content original reader variant

The shared installed reader may receive the already-adopted Request Content
Run and its original reader. Its existing input-kind query must recognize the
same nominal keyed Content Plan's Direct Row acquisition as the `query`
variant before the existing original acquisition handoff. This classification
uses the same live Run, Prepared and Request; it does not construct another
Query, declaration, provider, acquisition, Ledger or resource owner.

The selected keyed Plan must retain its original Direct Row acquisition and
requirement, without a provider replacement. Serialization-only Content has
no such Direct input and does not acquire one through this getter. The Pure
Plan keeps its existing Query/whole-input distinction. Foreign originals and
retired Run payloads refuse. Variant selection is immutable DATA and invokes
no current callback; the following original read constructor retains its own
pre-call admission, current fence, partial-child retention and cleanup duties.
Neither the variant nor release of a read alias acknowledges physical stop or
parent retirement.


## Mixed installed capture originals

A mixed Row/DuckDB prefix retains each occurrence's capacity in the SAME
checked Request Plan. The DuckDB preparation borrows its original requirement
and opaque installed capacity from that Plan after the original Run's current
check. It does not prepare a second Query or pending capacity envelope. The
existing Native/Broad selector still checks Account/current and its actual
selected configuration against those retained bounds before physical I/O.
The pending and installed envelope entry points share one acceptance predicate.
The Source also forwards its same three retained acquisition/evidence contract
originals; Run preparation does not reopen and parse those installation files.

The builtin DuckDB installation supplies its registered `builtin_source/0.1`
identity. Its private preparation map binds the original prepared object,
exact physical target and selected catalogue view to that installation's
binding CID. A copied or foreign preparation, retired installation or partial
bound inventory cannot become ordinary Saved custody.

The dispatch owner retains each original preparation's retirement method before
opening the first input. Completed captures retire through their original close
first. Only after pending physical cleanup has settled does that same owner
return still-unentered Row preparations, so an early sibling failure cannot
strand a later original read until global installation close. Unknown physical
work still blocks this cut. No read, retry, replacement Ledger or cleanup ACK is
created by returning an unentered preparation. Per-capture cleanup and complete
Run/preparation retirement remain different observation boundaries.

## Keyed relation on the original materializing Run

An ordinary Direct Source followed by a keyed relation borrows the same
Request's admitted Run Ledger. Optional cardinality estimates do not create
a second budget or turn an unknown row count into a checked bound. The
retained Plan supplies its original Direct capacity, generated sequences and
configured Compute; opening the keyed input does not check or compile again.
The same Request, Prepared and Source identities remain bound, including the
right-side key, version, correlation and current read authorization.

RowRun, lookup assembly and Compute reserve their actual demand on that same
finite Ledger before use and grow there as actual inputs arrive. A whole
execution ceiling is not an additional execution cost. Existing current and
post-callback original fences remain authoritative. Foreign Request, capacity,
Ledger or retired custody refuses without falling back to a standalone Run.
Compute stops before the borrowed lookup and Direct input are reclaimed;
their cleanup and final parent retirement remain separate duties. The
standalone path and Model/serialization purposes retain their own contracts.

## Salesforce response construction on the original reader

The installed Salesforce reader charges and retains each original response
before projection. Its raw-body inventory consists of the received prefix and
one next bounded transport buffer, including the first offending response. The
aggregate byte and response-count limits remain rejection limits; future pages
are not already allocated bodies.

The existing QueryRead retains the original body, path and digest with the
Source preflight cursor. Unicode and byte preflight observe wire geometry
before grammar construction. This geometry bounds malformed prefixes as well
as successful input; it is neither a parsed page nor authority to execute.
The same RowRun must admit the constructor peak before QueryRead transfers and
advances that same parser. A copied or changed body cannot consume the cursor.
The original JSON, node, depth, field, row and locator checks still decide
admission. Missing nullable cells, compound roles and multipicklist expansion
remain in the value-construction inventory.

Prior Describe material and the next query workspace have separate extents.
A large query body does not enlarge an already completed Describe parser.
Only one query page is pending; its original acknowledgment precedes the next
locator request. Interruption retires its pending parser through the existing
QueryRead, while the reader retains raw responses, failed children and physical
cleanup responsibilities. Neither parser retirement nor a quantity quote is a
physical-stop or Host-close acknowledgment.
