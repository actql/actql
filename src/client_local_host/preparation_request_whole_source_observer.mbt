///|
// Fixed evaluator scratch, not the future Maps/RowInput objects described by
// its returned quantities. Reserve it before any member observation/quotation.
// No original tree, path, String, member vector or schema field is copied.
//
// Bound nine active named frames including the entry closure: Whole input,
// Whole member, snapshot-selector, closed-field/issue-path, cursor-path,
// collection, map and checked scalar arithmetic. The direct closed-object
// wrapper is an alternative to the snapshot-selector, not another deep walk.
// The collection+map expansion uses its authoritative21H2R42W quotation
// extent (13H1R26W direct collection +8H1R16W map). The remaining seven
// frames are each bounded by20 coheld record/Option/pair headers,20 references
// and40 scalar slots. Parent member's opened/closed/issue/caller extents and
// their Options stay inside its20H bound while the child selector is quoted.
// This is a source-bound frame inventory, not spare bytes or body-node count;
// a changed call chain requires reviewing this term.
//
// Snapshot-selector quotation additionally constructs four fixed reference
// Arrays: allowed field names8, CID names4, CID values4, classifications5.
// The outer member observer owns the two-section Array. They coexist with
// member access/instance products and the scalar path/geometry pairs. Their
// key bodies remain borrowed; this term never prices an actual body-sized Map.
fn request_whole_source_observer_inventory_bytes() -> Int64? {
  guard @execution.preparation_array_representation(5L, 23L, false)
    is Some(arrays) else {
    return None
  }
  let member_access = @environment.member_access_construction_extent()
  let member_instance = @environment.member_instance_construction_extent()
  let collection_quote = @shape.collection_construction_quotation_extent()
  @execution.preparation_representation_cost({
    record_headers: 7L * 20L +
    collection_quote.record_headers +
    arrays.record_headers +
    member_access.record_headers +
    member_instance.record_headers +
    2L,
    reference_slots: 7L * 20L +
    collection_quote.reference_slots +
    arrays.reference_slots +
    member_access.reference_slots +
    member_instance.reference_slots,
    scalar_words: 7L * 40L +
    collection_quote.scalar_words +
    arrays.scalar_words +
    member_access.scalar_words +
    member_instance.scalar_words +
    5L,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  })
}

///|
// Compute the fixed inventory once at module initialization, not inside the
// Request whose first grow it describes. No member or Request is observed.
let request_whole_source_observer_inventory : Int64 = request_whole_source_observer_inventory_bytes().unwrap()

///|
fn request_whole_source_observer_bytes() -> Int64? {
  Some(request_whole_source_observer_inventory)
}

///|
// Original Plan-control backing BEFORE ProgramPlanReserved. Each of the two
// installed_direct_occurrences_layout calls creates two composition Arrays,
// four unit literals, three array-quotation results, two composed/validated
// unit results and the final cost/pair alternatives. Co-count all constructor
// events, including sequential Some results: each positive layout is bounded
// by110H/48R/224W (94 direct headers, ten mutable scalar cells across the
// two composition calls, four total cells in the cost projections, and two
// refusal alternatives). The pinned JS
// compiler emits five MutLocal cells per composition, with an indexed loop
// and no iterator object. Include both literal Array backings and their
// slots, extent/checked-scalar tags and payloads;224W includes all14 cells.
// The zero-input alternative is smaller. The same route/grow/return carriers
// add12H/8R/20W. These are allocated products, not nonrecursive VM frames.
// The observer's fixed quantity is already a module-owned scalar above; its
// member-observation scratch is separately reserved by the first domain grow.
// No original input, Source, tree, String or policy-maximum vector is copied.
let request_whole_source_initial_quotation_bytes : Int64 = @execution.preparation_representation_cost({
    record_headers: 2L * 110L + 12L,
    reference_slots: 2L * 48L + 8L,
    scalar_words: 2L * 224L + 20L,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  },
).unwrap()
