///|
/// Constructor-only DATA for the existing one-task numeric Values route.
/// No executor, provider kernel, grant or cleanup owner is opened by this data.
priv struct ClosedValuesModuleConstructionLayout {
  retained : @execution.PreparationRepresentationUnits
}

///|
// Returned controls, excluding the four snapshot/selection arrays and the
// ClientPreparedLocalConfiguration already funded by the initial owner:
// Values provider3H6R2W; selected Some1H1R1W; capacity+Some2H1R3W;
// FixedComputeCapacity1H1R3W; factory base ExecutionCapacity1H0R2W;
// module excluding four array links1H5R1W; dispatch1H12R0W;
// three other arrays6H5R7W; envelope+Some2H1R4W; retained/transfer2H0R4W;
// input/output/metadata carriers7H7R7W; registration6H14R7W;
// configuration None->Some delta1H2R0W; physical sequence6H22R9W.
// The last sequence is an immutable selected-step view of the SAME original.
// Payload bodies, schemas, policies, source rows and Strings stay borrowed.
let closed_values_module_retained_output : ClosedValuesModuleConstructionLayout = {
  retained: {
    record_headers: 40L,
    reference_slots: 77L,
    scalar_words: 50L,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  },
}

///|
// Without retained output: three output carriers are absent, and the output
// policy field is an inline tag instead of a reference. The selected module
// and input-metadata controls still exist; no caller profile is substituted.
let closed_values_module_without_output : ClosedValuesModuleConstructionLayout = {
  retained: {
    record_headers: 37L,
    reference_slots: 73L,
    scalar_words: 48L,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  },
}

///|
fn closed_values_module_construction_layout(
  retained_output : Bool,
) -> ClosedValuesModuleConstructionLayout {
  if retained_output {
    closed_values_module_retained_output
  } else {
    closed_values_module_without_output
  }
}

///|
// Call-expanded outer construction: local configuration/bundle/closure+Some,
// installed bundle wrappers, three implementation records/arrays, fixed tuple
// and argument carriers:17H34R12W. The physical append Array adds2H9R2W.
// These coexist with each private inner peak and the factory's returned Array.
let closed_values_module_outer : @execution.PreparationRepresentationUnits = {
  record_headers: 19L,
  reference_slots: 43L,
  scalar_words: 14L,
  owned_utf16_units: 0L,
  owned_wire_bytes: 0L,
}

///|
// The actual one-task generated_sequence_capacity private inventory dominates:
// three typed lists4/10/2, their item records, arithmetic Some and quote folds:
//41H19R92W. Other complete inner alternatives are default-provider construction
//35H76R30W, IO validation4H2R29W, registry installation632B,
// policy refinement1048B and input/output metadata736B. Final configured
// capacity projection adds at most9H14R20W=416B: the old raw record/limits,
// two checked-add Some, capacity/tuple/Option carriers and returned Ok. Its
// new limits/final source-free record use the retained slots; they are not
// counted again as old temporary originals. These helpers return before the
// next begins. No represented value-node/row buffers are allocated.
let closed_values_module_private : @execution.PreparationRepresentationUnits = {
  record_headers: 41L,
  reference_slots: 19L,
  scalar_words: 92L,
  owned_utf16_units: 0L,
  owned_wire_bytes: 0L,
}

///|
/// The factory's returned Array survives the inner module/selection calls.
/// Only its private constructor/eligibility scratch is disjoint from those
/// calls. Family inventories come from the SAME fixed installed composition,
/// not JavaScript knobs or a capacity issuer. All tariff/addition is shared.
fn closed_values_module_construction_execution(
  family_array : @execution.PreparationRepresentationUnits,
  family_temporary : @execution.PreparationRepresentationUnits,
) -> Int64? {
  guard @execution.preparation_representation_cost(family_array) is Some(array) &&
    @execution.preparation_representation_cost(family_temporary) is Some(family) &&
    @execution.preparation_representation_cost(closed_values_module_outer)
    is Some(outer) &&
    @execution.preparation_representation_cost(closed_values_module_private)
    is Some(inner) &&
    @execution.checked_preparation_add_product(outer, array, 1L) is Some(base) else {
    return None
  }
  @execution.checked_preparation_add_product(
    base,
    Int64::max(inner, family),
    1L,
  )
}
