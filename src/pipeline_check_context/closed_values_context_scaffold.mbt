///|
/// Fixed constructor scaffold for the initial one-stage, one-Values, one-Result
/// preparation route. Source/typed rows, topology, identity, Catalog, policies,
/// capacity proof bodies, core contract bodies and publication payloads are
/// separate owners; this inventory never implies their cost is zero.
pub(all) struct ClosedValuesContextScaffoldLayout {
  record_headers : Int64
  reference_slots : Int64
  scalar_words : Int64
  record_instances : Int
  array_owners_upper : Int
}

///|
/// Source audit table: closed-context-owner-table-draft.json (named types and
/// constructor paths). Fifteen resolution-index versions conservatively coexist
/// across the twelve initial/mandatory passes and three optional numeric passes.
/// StageContexts has four shallow construction versions; SelectedPolicyContext
/// three; BoundParameters and ReconciledContexts two. Their shared children may
/// use less: reserving an array per field/version is a conservative upper, not
/// an assertion that aliases became newly owned arrays. All these small arrays
/// have at most one item; eight slots cover append, copy and fixed construction.
pub fn closed_values_context_scaffold_layout() -> ClosedValuesContextScaffoldLayout {
  {
    // Named records81; Arrays67 each wrapper/backing+old backing3;
    // possible Some carriers13; eight scratch Maps each record/backing +
    // one Entry/two Some carriers (empty Maps use less).
    record_headers: 81L + 3L * 67L + 13L + 8L * 5L,
    reference_slots: 249L + 9L * 67L + 13L + 8L * 7L,
    // Reserve both scalar/reference backing alternatives conservatively;
    // reconciliation uses actual typed slots, never bills both as actual owners.
    scalar_words: 214L + 10L * 67L + 13L + 8L * 18L,
    record_instances: 81,
    array_owners_upper: 67,
  }
}
