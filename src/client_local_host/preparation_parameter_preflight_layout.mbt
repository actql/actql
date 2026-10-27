///|
// Call-expanded quotation controls, not the represented default/type bodies.
// Original indexed preflight inventory:67H13R147W. Two checked collection
// expansions each own21H2R42W; two indexed extent sums10H2R20W; path input
//1H9W/checked count1H2W; traversal input1H9W; issue input1H3W;
// issue/path sum5H1R10W; NFC descriptor/Some4H2R9W; final2H4R1W.
// Conversion/3-item Array/composition/tariff/checked peaks/quote carriers add
//38H7R83W. These are fixed constructor maxima, not decoded-node storage.
let parameter_preflight_quote_controls : @execution.PreparationRepresentationUnits = {
  record_headers: 67L + 38L,
  reference_slots: 13L + 7L,
  scalar_words: 147L + 83L,
  owned_utf16_units: 0L,
  owned_wire_bytes: 0L,
}

///|
// Holder1H8R5W; input Some1H1R1W; original debit/result and two checked adds
//4H1R7W; reserve/typed failure carriers4H4R4W; geometry/Some/spine3H1R14W;
// exact cursor-depth and returned observer tuples2H1R4W;
// original preflight/read-input/Budget/usage/Results/tuples7H7R11W;
// retained outcome Some1H1R1W and active work Some1H1R1W. Co-counted
// alternatives cover absent input and failure, not only the success branch.
let parameter_preflight_driver_controls : @execution.PreparationRepresentationUnits = {
  record_headers: 23L + 2L,
  reference_slots: 25L + 1L,
  scalar_words: 45L + 4L,
  owned_utf16_units: 0L,
  owned_wire_bytes: 0L,
}

///|
let parameter_preflight_initial_controls : @execution.PreparationRepresentationUnits = {
  let work = @resources.preparation_phase_work_construction_inventory()
  @execution.compose_preparation_representation([
    parameter_preflight_quote_controls,
    parameter_preflight_driver_controls,
    {
      record_headers: work.record_headers,
      reference_slots: work.reference_slots,
      scalar_words: work.scalar_words,
      owned_utf16_units: 0L,
      owned_wire_bytes: 0L,
    },
  ]).unwrap()
}

///|
let parameter_preflight_initial_bytes : Int64 = @execution.preparation_representation_cost(
  parameter_preflight_initial_controls,
).unwrap()

///|
/// Immutable recipe, NOT a prepaid entrance. Begin adds it once to outside
/// debits. The actual caller backs borrowed input/limits and the pre-resize
/// getter/current/resize frame before entry; no physical supply is claimed.
pub fn parameter_declaration_preflight_initial_inventory() -> @execution.PreparationRepresentationUnits {
  parameter_preflight_initial_controls
}

///|
fn parameter_preflight_construction_bytes(
  geometry : @decode.SubtreeConstructionGeometry,
  root_path_depth : Int,
  limits : @parameters.DeclarationLimits,
) -> Int64? {
  guard @parameters.declaration_preflight_construction_inventory(
      geometry, root_path_depth, limits,
    )
    is Some(original) else {
    return None
  }
  let key : @execution.PreparationRepresentationUnits = match
    original.key_normalization {
    None =>
      {
        record_headers: 0L,
        reference_slots: 0L,
        scalar_words: 0L,
        owned_utf16_units: 0L,
        owned_wire_bytes: 0L,
      }
    Some(value) =>
      {
        record_headers: value.record_headers,
        reference_slots: value.reference_slots,
        scalar_words: value.scalar_words,
        owned_utf16_units: value.owned_utf16_units,
        owned_wire_bytes: 0L,
      }
  }
  guard @execution.compose_preparation_representation([
      {
        record_headers: original.traversal.record_headers,
        reference_slots: original.traversal.reference_slots,
        scalar_words: original.traversal.scalar_words,
        owned_utf16_units: 0L,
        owned_wire_bytes: 0L,
      },
      {
        record_headers: original.refusal.record_headers,
        reference_slots: original.refusal.reference_slots,
        scalar_words: original.refusal.scalar_words,
        owned_utf16_units: 0L,
        owned_wire_bytes: 0L,
      },
      key,
    ])
    is Some(units) else {
    return None
  }
  @execution.preparation_representation_cost(units)
}
