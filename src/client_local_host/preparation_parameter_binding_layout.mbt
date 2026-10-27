///|
// Decoder quote: actual width Some1H2W; key-count record/Some2H1R5W;
// selected count tuple1H4W; collection input+expansion22H2R51W;
// original path input/check/collection23H2R53W; sum5H1R10W:
//54H6R125W. Parameter adds its input/expansion22H2R51W, issue/sum6H1R13W
// and the final original closed-body sum5H1R10W:87H10R199W.
// Conversion/tariff6H15W, three debit adds3H6W, stored quote carriers
//2H1R3W give98H11R223W. Co-count sequential constructors, not decoded data.
let parameter_binding_header_quote_controls : @execution.PreparationRepresentationUnits = {
  record_headers: 98L,
  reference_slots: 11L,
  scalar_words: 223L,
  owned_utf16_units: 0L,
  owned_wire_bytes: 0L,
}

///|
// Continuation4R5W; original reader/state/result3H5R3W; input/outcome
// Options2H2R2W; original debit/result and two checked adds4H1R7W;
// reserve/typed-invalid/outer-return/phase refusal6H4R6W;
// borrowed ancestry tuple1H2W and clear result1H1W:18H16R26W.
// The original metadata match tuple1H2W and Host Work/Err carriers2H2R2W
// coexist with the separately owned complete work-receipt packet below.
let parameter_binding_driver_controls : @execution.PreparationRepresentationUnits = {
  record_headers: 21L,
  reference_slots: 18L,
  scalar_words: 30L,
  owned_utf16_units: 0L,
  owned_wire_bytes: 0L,
}

///|
let parameter_binding_initial_controls : @execution.PreparationRepresentationUnits = {
  let work = @resources.preparation_phase_work_construction_inventory()
  @execution.compose_preparation_representation([
    parameter_binding_header_quote_controls,
    parameter_binding_driver_controls,
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
let parameter_binding_initial_bytes : Int64 = @execution.preparation_representation_cost(
  parameter_binding_initial_controls,
).unwrap()

///|
/// Immutable initial constructor packet, not capacity, a minimum physical
/// supply or funding for later source preflight/Value/result construction.
pub fn parameter_binding_preparation_initial_inventory() -> @execution.PreparationRepresentationUnits {
  parameter_binding_initial_controls
}

///|
fn parameter_binding_header_construction_bytes(
  original : @parameters.BindingReadInput,
  root_path_depth : Int,
) -> Int64? {
  guard @parameters.binding_header_construction_extent(
      original, root_path_depth,
    )
    is Some(storage) else {
    return None
  }
  @execution.preparation_representation_cost({
    record_headers: storage.record_headers,
    reference_slots: storage.reference_slots,
    scalar_words: storage.scalar_words,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  })
}
