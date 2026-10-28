///|
// Additional call-expanded controls around the original read's quotation:
// two conversions2H10W/tariffs10H20W, three checked sums3H6W,
// split tuple/Some2H1R3W, stored Some1H1R1W, two debit adds2H4W and original
// work-bound Some1H2W. The domain backs these BEFORE metadata/quotation;
// they retire only after the original semantic selection returns successfully.
let program_source_resolution_quote_bytes : Int64 = {
  let original = @context.source_registration_resolution_quotation_extent()
  @execution.preparation_representation_cost(
    program_structure_units(
      original.record_headers + 21L,
      original.reference_slots + 2L,
      original.scalar_words + 46L,
    ),
  ).unwrap()
}

///|
let program_source_resolution_metadata_peak_bytes : Int64 = program_source_extent_cost(
    @context.source_registration_resolution_inspection_extent(),
  ).unwrap() +
  program_source_resolution_quote_bytes

///|
let program_source_resolution_metadata_retained_bytes : Int64 = program_source_extent_cost(
    @context.source_registration_resolution_inspection_retained_extent(),
  ).unwrap() +
  program_source_resolution_quote_bytes

///|
let program_source_resolution_driver_bytes : Int64 = program_source_extent_cost(
  @context.source_registration_resolution_driver_extent(),
).unwrap()

///|
let program_source_resolution_driver_retained_bytes : Int64 = program_source_extent_cost(
  @context.source_registration_resolution_driver_retained_extent(),
).unwrap()

///|
// The SAME original read supplies body geometry/limits. Text remains UTF16
// through the common tariff, never cast to wire bytes or replaced by policy.
fn program_source_resolution_body_bytes(
  read : @context.SourceRegistrationRead,
) -> (Int64, Int64)? {
  guard @context.source_registration_resolution_construction(read)
    is Some(inventory) &&
    @execution.preparation_representation_cost({
      record_headers: inventory.returned.record_headers,
      reference_slots: inventory.returned.reference_slots,
      scalar_words: inventory.returned.scalar_words,
      owned_utf16_units: inventory.returned_utf16_units,
      owned_wire_bytes: 0L,
    })
    is Some(returned) &&
    @execution.preparation_representation_cost({
      record_headers: inventory.temporary.record_headers,
      reference_slots: inventory.temporary.reference_slots,
      scalar_words: inventory.temporary.scalar_words,
      owned_utf16_units: inventory.temporary_utf16_units,
      owned_wire_bytes: 0L,
    })
    is Some(temporary) &&
    @execution.checked_preparation_add_product(returned, temporary, 1L)
    is Some(peak) &&
    @execution.checked_preparation_add_product(
      peak, program_source_resolution_driver_bytes, 1L,
    )
    is Some(peak) &&
    @execution.checked_preparation_add_product(
      returned, program_source_resolution_driver_retained_bytes, 1L,
    )
    is Some(held) else {
    return None
  }
  Some((peak, held))
}
