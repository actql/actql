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

The focused Core and explicit-port Node cases exercise full input beyond a
Query result bound, original key refusal, callback/current fences, pending
physical close, same-Request adoption and the still-pending Compute root.
They do not establish the ordinary SDK, Account, authenticated transport,
publication, separate-process Saved or final normal-distribution acceptance.
