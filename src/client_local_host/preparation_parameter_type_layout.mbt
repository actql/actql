///|
// Call-expanded original phase quote: returned inventory12H1R30W;
// two collection expansions42H4R84W; syntax+control sums12H2R26W;
// key selector2H1R5W; scratch input1H9W; original path+two sums33H4R73W;
// two checked path adds2H4W; NFC descriptor3H1R8W; phase result2H4R2W:
//109H17R241W. Parameter limits/attachment/issues/copy15H6R31W gives
//124H23R272W. Three conversions3H15W; four tariffs20H40W; same sort2H1R6W;
// two sums2H4W; returned split2H1R3W; five debit adds5H10W; stored quote2H1R3W:
// The next-entry peak maximum adds one temporary tuple1H2W:
//161H26R355W. All are constructor controls, not type/default bodies.
let parameter_type_quote_controls : @execution.PreparationRepresentationUnits = {
  record_headers: 161L,
  reference_slots: 26L,
  scalar_words: 355L,
  owned_utf16_units: 0L,
  owned_wire_bytes: 0L,
}

///|
fn parameter_type_construction_bytes(
  original : @parameters.DeclarationReadInput,
  root_path_depth : Int,
) -> (Int64, Int64)? {
  guard @parameters.declaration_type_construction_inventory(
      original, root_path_depth,
    )
    is Some(inventory) else {
    return None
  }
  let returned : @execution.PreparationRepresentationUnits = {
    record_headers: inventory.returned.record_headers,
    reference_slots: inventory.returned.reference_slots,
    scalar_words: inventory.returned.scalar_words,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }
  let temporary : @execution.PreparationRepresentationUnits = {
    record_headers: inventory.temporary.record_headers,
    reference_slots: inventory.temporary.reference_slots,
    scalar_words: inventory.temporary.scalar_words,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }
  let normalized : @execution.PreparationRepresentationUnits = match
    inventory.normalization {
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
  guard @execution.preparation_representation_cost(returned) is Some(r) &&
    @execution.preparation_representation_cost(temporary) is Some(t) &&
    @execution.preparation_representation_cost(normalized) is Some(n) &&
    @execution.checked_preparation_add_product(t, n, 1L) is Some(t) else {
    return None
  }
  let sorted = if inventory.sort_fields == 0 {
    0L
  } else {
    guard closed_values_sort_scratch_layout(inventory.sort_fields)
      is Some(units) &&
      @execution.preparation_representation_cost(units) is Some(bytes) else {
      return None
    }
    bytes
  }
  guard @execution.checked_preparation_add_product(t, sorted, 1L) is Some(t) else {
    return None
  }
  Some((r, t))
}
