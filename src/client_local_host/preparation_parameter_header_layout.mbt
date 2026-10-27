///|
// Call-expanded Header quote, independent of the earlier preflight quote.
// O(1) length/issue Options2H4W; header descriptor1H9W; collection21H2R42W;
// original path input/check/collection23H2R53W; three sums15H3R30W;
// shared issue extent1H3W; returned inventory/Some2H2R2W:65H9R143W.
// Conversion1H5W; SAME existing builtin sort record/Some2H1R6W; two
// distinct tariff calls10H20W; sum+three outside-debit adds4H8W;
// stored quote tuple/Some2H1R3W =>84H11R185W. Phase quotes run only
// after the prior synchronous quote returned, never as simultaneous peaks.
let parameter_header_quote_controls : @execution.PreparationRepresentationUnits = {
  record_headers: 84L,
  reference_slots: 11L,
  scalar_words: 185L,
  owned_utf16_units: 0L,
  owned_wire_bytes: 0L,
}

///|
// This is the source-proved maximum of two independent quote constructors,
// not spare preflight capacity or a second tariff. Actual body storage below
// is additional; previous failure/input/outcome aliases remain with owners.
let parameter_declaration_quote_controls : @execution.PreparationRepresentationUnits = {
  record_headers: Int64::max(
    parameter_preflight_quote_controls.record_headers,
    parameter_header_quote_controls.record_headers,
  ),
  reference_slots: Int64::max(
    parameter_preflight_quote_controls.reference_slots,
    parameter_header_quote_controls.reference_slots,
  ),
  scalar_words: Int64::max(
    parameter_preflight_quote_controls.scalar_words,
    parameter_header_quote_controls.scalar_words,
  ),
  owned_utf16_units: 0L,
  owned_wire_bytes: 0L,
}

///|
fn parameter_header_construction_bytes(
  root : @decode.Cursor?,
  root_path_depth : Int,
  limits : @parameters.DeclarationLimits,
) -> Int64? {
  guard @parameters.declaration_header_construction_inventory(
      root, root_path_depth, limits,
    )
    is Some(original) else {
    return None
  }
  let units : @execution.PreparationRepresentationUnits = {
    record_headers: original.storage.record_headers,
    reference_slots: original.storage.reference_slots,
    scalar_words: original.storage.scalar_words,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }
  guard @execution.preparation_representation_cost(units) is Some(storage) else {
    return None
  }
  let sort = if original.sort_fields == 0 {
    0L
  } else {
    // Same pinned sort constructor already used by the Values callers. No
    // duplicated stack/partition/backing coefficients or field-width guess.
    guard closed_values_sort_scratch_layout(original.sort_fields) is Some(units) &&
      @execution.preparation_representation_cost(units) is Some(bytes) else {
      return None
    }
    bytes
  }
  @execution.checked_preparation_add_product(storage, sort, 1L)
}
