///|
// Existing call-expanded Catalog quotation families, now in their LATER domain:
// binder223H66R457W; prelude61H37R107W; registry128H81R236W;
// emitter/Contents/reconcile209H113R424W; references/policies/values349H172R711W;
// Carrier and Requests each159H84R321W. Binder223 already includes its
// Stage-collection bridge23H2R52W; do not add that bridge again. These co-count
// sequential quote, receipt and typed-return
// alternatives, not input bodies, policy headroom or a minimum/RSS claim.
let program_check_quote_controls : @execution.PreparationRepresentationUnits = {
  record_headers: 223L + 61L + 128L + 209L + 349L + 159L + 159L,
  reference_slots: 66L + 37L + 81L + 113L + 172L + 84L + 84L,
  scalar_words: 457L + 107L + 236L + 424L + 711L + 321L + 321L,
  owned_utf16_units: 0L,
  owned_wire_bytes: 0L,
}

///|
// Actual holder1H25R9W and immutable argument snapshot1H7R; twenty-four live Some
// alternatives24H24R24W; five cached pair records5H10W; retained inventory1H9W;
// original debit/Result2H1R3W and entry typed alternatives2H2R2W.
// Borrowed Program/Source/Catalog/evidence backing is never copied into this
// fixed packet. The original Source compiler association adds one target-tuple
// reference slot; input-sized metadata/binder and later domains grow separately.
// Two scalar actual-work observations (2W) remain in this same child until the
// Request copies them before its existing typed continuation clears the child.
// Remaining-check and compiler call observers add two temporary Ref/Some pairs
// (4H/2R/4W), conservatively co-counted without assuming collection or reuse.
let program_check_driver_controls : @execution.PreparationRepresentationUnits = {
  record_headers: 1L + 1L + 24L + 5L + 1L + 2L + 2L + 4L,
  reference_slots: 25L + 7L + 24L + 1L + 2L + 1L + 2L,
  scalar_words: 9L + 24L + 10L + 9L + 3L + 2L + 2L + 4L,
  owned_utf16_units: 0L,
  owned_wire_bytes: 0L,
}

///|
let program_check_initial_controls : @execution.PreparationRepresentationUnits = @execution.compose_preparation_representation([
    program_check_quote_controls, program_check_driver_controls,
  ],
).unwrap()

///|
let program_check_initial_control_bytes : Int64 = @execution.preparation_representation_cost(
  program_check_initial_controls,
).unwrap()

///|
/// Installed DATA before entry; not physical supply, work credit or a grant.
pub fn program_check_preparation_initial_inventory() -> @execution.PreparationRepresentationUnits {
  program_check_initial_controls
}

///|
let program_check_input_observer_bytes : Int64 = {
  let c = @shape.collection_construction_extent(
    @context.capacity_input_construction_observation_inventory(),
  ).unwrap()
  @execution.preparation_representation_cost(
    program_structure_units(c.record_headers, c.reference_slots, c.scalar_words),
  ).unwrap()
}
