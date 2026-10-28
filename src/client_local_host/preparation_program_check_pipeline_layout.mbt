///|
// Same original quote/current/debit frame as collection and resolution:
// two conversions2H10W/tariffs10H20W, three checked sums3H6W,
// split tuple/Some2H1R3W, stored Some1H1R1W, two debit adds2H4W,
// original work-bound Some1H2W. No body, policy or foreign layout is assumed.
let program_source_pipeline_quote_bytes : Int64 = {
  let original = @context.source_registration_pipeline_quotation_extent()
  @execution.preparation_representation_cost(
    program_structure_units(
      original.record_headers + 21L,
      original.reference_slots + 2L,
      original.scalar_words + 46L,
    ),
  ).unwrap()
}

///|
let program_source_pipeline_driver_bytes : Int64 = program_source_extent_cost(
  @context.source_registration_pipeline_driver_extent(),
).unwrap()

///|
let program_source_pipeline_driver_retained_bytes : Int64 = program_source_extent_cost(
  @context.source_registration_pipeline_driver_retained_extent(),
).unwrap()

///|
fn program_source_pipeline_body_bytes(
  read : @context.SourceRegistrationRead,
) -> (Int64, Int64)? {
  guard @context.source_registration_pipeline_construction(read)
    is Some(inventory) &&
    program_source_extent_cost(inventory.returned) is Some(returned) &&
    program_source_extent_cost(inventory.temporary) is Some(temporary) &&
    @execution.checked_preparation_add_product(returned, temporary, 1L)
    is Some(peak) &&
    @execution.checked_preparation_add_product(
      peak, program_source_pipeline_driver_bytes, 1L,
    )
    is Some(peak) &&
    @execution.checked_preparation_add_product(
      returned, program_source_pipeline_driver_retained_bytes, 1L,
    )
    is Some(held) else {
    return None
  }
  Some((peak, held))
}
