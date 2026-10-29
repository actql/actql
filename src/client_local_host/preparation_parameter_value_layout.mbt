///|
// Call-expanded original Value body52H12R120W; full Value phase adds
// checked/sum6H1R13W, fixed control expansion22H2R51W, path24H2R55W,
// six sums30H6R60W and phase result2H4R2W:136H27R301W.
// Parameter adds optional phase1H1R1W, declaration/sum6H1R13W, key selector
//2H1R5W, two collection inputs2H18W, scalar tuple1H5W, path22H2R51W,
// two expansions42H4R84W, issue1H3W, four sums20H4R40W and final2H5R1W:
// The original option-pair adds1H2R:236H47R522W. Parameter-owned Value
// Limits/issue/sums/copy add13H5R28W:249H52R550W.
// Five conversions5H25W/five tariffs25H50W/temp sum1H2W/
// returned split2H1R3W/five debit adds5H10W/max tuple1H2W/stored quote2H1R3W give
//290H54R645W. A sequential quote maximum, not value storage or free allowance.
let parameter_value_quote_controls : @execution.PreparationRepresentationUnits = {
  record_headers: 290L,
  reference_slots: 54L,
  scalar_words: 645L,
  owned_utf16_units: 0L,
  owned_wire_bytes: 0L,
}

///|
fn parameter_value_construction_bytes(
  original : @parameters.DeclarationReadInput,
  root_path_depth : Int,
) -> (Int64, Int64)? {
  guard @parameters.declaration_value_construction_inventory(
      original, root_path_depth,
    )
    is Some(inventory) else {
    return None
  }
  let retained : @execution.PreparationRepresentationUnits = {
    record_headers: inventory.returned.record_headers,
    reference_slots: inventory.returned.reference_slots,
    scalar_words: inventory.returned.scalar_words,
    owned_utf16_units: match inventory.value {
      None => 0L
      Some(v) => v.returned_utf16_units
    },
    owned_wire_bytes: 0L,
  }
  let metadata : @execution.PreparationRepresentationUnits = {
    record_headers: inventory.metadata.record_headers,
    reference_slots: inventory.metadata.reference_slots,
    scalar_words: inventory.metadata.scalar_words,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }
  let constraints : @execution.PreparationRepresentationUnits = {
    record_headers: inventory.constraints.record_headers,
    reference_slots: inventory.constraints.reference_slots,
    scalar_words: inventory.constraints.scalar_words,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }
  guard @execution.preparation_representation_cost(retained) is Some(r) &&
    @execution.preparation_representation_cost(metadata) is Some(m) &&
    @execution.preparation_representation_cost(constraints) is Some(c) else {
    return None
  }
  let value = match inventory.value {
    None => 0L
    Some(value) => {
      let temporary : @execution.PreparationRepresentationUnits = {
        record_headers: value.temporary.record_headers,
        reference_slots: value.temporary.reference_slots,
        scalar_words: value.temporary.scalar_words,
        owned_utf16_units: value.temporary_utf16_units,
        owned_wire_bytes: 0L,
      }
      let normalization : @execution.PreparationRepresentationUnits = match
        value.normalization {
        None =>
          {
            record_headers: 0L,
            reference_slots: 0L,
            scalar_words: 0L,
            owned_utf16_units: 0L,
            owned_wire_bytes: 0L,
          }
        Some(n) =>
          {
            record_headers: n.record_headers,
            reference_slots: n.reference_slots,
            scalar_words: n.scalar_words,
            owned_utf16_units: n.owned_utf16_units,
            owned_wire_bytes: 0L,
          }
      }
      guard @execution.preparation_representation_cost(temporary) is Some(t) &&
        @execution.preparation_representation_cost(normalization) is Some(n) &&
        @execution.checked_preparation_add_product(t, n, 1L) is Some(t) else {
        return None
      }
      t
    }
  }
  // metadata returns before Value admission; its scratch returns before the
  // original Parameter constraints. Retained output coexists with their max.
  Some((r, Int64::max(value, Int64::max(m, c))))
}
