///|
// Source quote: original length Some1H2W; two collection inputs2H18W,
// two generic expansions42H4R84W, two sums10H2R20W, inventory/Some2H3R2W;
// two conversions2H10W/tariffs10H20W, split tuple/Some2H1R4W,
// five checked debit additions5H10W and stored quote2H1R3W:78H11R173W.
// This sequential phase is compared with the other actual quote constructors,
// never supplied as unrelated Values layout, spare extent or a resource grant.
let parameter_source_quote_controls : @execution.PreparationRepresentationUnits = {
  record_headers: 78L,
  reference_slots: 11L,
  scalar_words: 173L,
  owned_utf16_units: 0L,
  owned_wire_bytes: 0L,
}

///|
// Fixed binding Source descriptor3H2R7W; two conversions2H10W/tariffs10H20W;
// split tuple/Some2H1R3W; five checked adds5H10W; stored quote2H1R3W.
let parameter_source_binding_quote_controls : @execution.PreparationRepresentationUnits = {
  record_headers: 24L,
  reference_slots: 4L,
  scalar_words: 53L,
  owned_utf16_units: 0L,
  owned_wire_bytes: 0L,
}

///|
fn parameter_source_construction_bytes(
  program : @syntax.Program,
) -> (Int64, Int64, Int64)? {
  guard @stages.source_construction_inventory(program) is Some(inventory) &&
    @execution.preparation_representation_cost({
      record_headers: inventory.returned.record_headers,
      reference_slots: inventory.returned.reference_slots,
      scalar_words: inventory.returned.scalar_words,
      owned_utf16_units: 0L,
      owned_wire_bytes: 0L,
    })
    is Some(returned) &&
    @execution.preparation_representation_cost({
      record_headers: inventory.temporary.record_headers,
      reference_slots: inventory.temporary.reference_slots,
      scalar_words: inventory.temporary.scalar_words,
      owned_utf16_units: 0L,
      owned_wire_bytes: 0L,
    })
    is Some(temporary) else {
    return None
  }
  Some((returned, temporary, inventory.maximum_work))
}

///|
fn parameter_source_binding_construction_bytes() -> (Int64, Int64)? {
  let inventory = @stages.source_binding_construction_inventory()
  guard @execution.preparation_representation_cost({
      record_headers: inventory.returned.record_headers,
      reference_slots: inventory.returned.reference_slots,
      scalar_words: inventory.returned.scalar_words,
      owned_utf16_units: 0L,
      owned_wire_bytes: 0L,
    })
    is Some(returned) &&
    @execution.preparation_representation_cost({
      record_headers: inventory.temporary.record_headers,
      reference_slots: inventory.temporary.reference_slots,
      scalar_words: inventory.temporary.scalar_words,
      owned_utf16_units: 0L,
      owned_wire_bytes: 0L,
    })
    is Some(temporary) else {
    return None
  }
  Some((returned, temporary))
}
