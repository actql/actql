///|
// Source's actual inventory quotation and the shared expansion owner, plus
// conversion/tariff6H15W, peak sum1H2W, pair/Some2H1R3W, retained Some1H1R1W,
// two debit sums2H4W and original work-bound Some1H2W. No repeated Index quote.
let program_source_local_groups_quote_bytes : Int64 = {
  let original = @context.source_registration_local_groups_quotation_extent()
  let expansion = @shape.collection_construction_quotation_extent()
  @execution.preparation_representation_cost(
    program_structure_units(
      original.record_headers + expansion.record_headers + 13L,
      original.reference_slots + expansion.reference_slots + 2L,
      original.scalar_words + expansion.scalar_words + 27L,
    ),
  ).unwrap()
}

///|
let program_source_local_groups_driver_bytes : Int64 = program_source_extent_cost(
  @context.source_registration_local_groups_driver_extent(),
).unwrap()

///|
fn program_source_local_groups_body_bytes(
  read : @context.SourceRegistrationRead,
) -> (Int64, Int64)? {
  guard @context.source_registration_local_groups_construction(read)
    is Some(inventory) &&
    @shape.collection_construction_extent(inventory) is Some(expanded) &&
    program_source_extent_cost(expanded) is Some(held) &&
    @execution.checked_preparation_add_product(
      held, program_source_local_groups_driver_bytes, 1L,
    )
    is Some(peak) else {
    return None
  }
  Some((peak, held))
}
