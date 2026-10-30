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
