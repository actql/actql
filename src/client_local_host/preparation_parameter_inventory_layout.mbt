///|
// Two collection inputs2H18W/expansions42H4R84W; fixed current controls1H3W;
// one extent sum5H1R10W; descriptor/Some2H3R1W:52H8R116W.
// Two conversions2H10W; distinct tariffs10H20W; five checked adds5H10W;
// original length Some1H2W; returned split tuple/Some2H1R3W; stored quote tuple/Some2H1R3W:74H10R164W.
// This complete fixed quote fits the proved sequential maximum, not spare
// preflight extent. Dynamic stack and retained observations are additional.
let parameter_inventory_quote_controls : @execution.PreparationRepresentationUnits = {
  record_headers: 74L,
  reference_slots: 10L,
  scalar_words: 164L,
  owned_utf16_units: 0L,
  owned_wire_bytes: 0L,
}

///|
fn parameter_inventory_construction_bytes(
  nodes : Int,
  declarations : Int,
) -> (Int64, Int64)? {
  guard @parameters.declaration_read_construction_inventory(nodes, declarations)
    is Some(original) else {
    return None
  }
  let retained : @execution.PreparationRepresentationUnits = {
    record_headers: original.retained.record_headers,
    reference_slots: original.retained.reference_slots,
    scalar_words: original.retained.scalar_words,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }
  let temporary : @execution.PreparationRepresentationUnits = {
    record_headers: original.temporary.record_headers,
    reference_slots: original.temporary.reference_slots,
    scalar_words: original.temporary.scalar_words,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }
  guard @execution.preparation_representation_cost(retained) is Some(r) &&
    @execution.preparation_representation_cost(temporary) is Some(t) else {
    return None
  }
  Some((r, t))
}
