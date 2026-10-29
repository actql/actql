///|
fn compilation_metadata_repeat_units(
  value : @execution.PreparationRepresentationUnits,
  count : Int64,
) -> @execution.PreparationRepresentationUnits? {
  if count < 0L {
    return None
  }
  guard @execution.checked_preparation_add_product(
      0L,
      value.record_headers,
      count,
    )
    is Some(h) &&
    @execution.checked_preparation_add_product(0L, value.reference_slots, count)
    is Some(r) &&
    @execution.checked_preparation_add_product(0L, value.scalar_words, count)
    is Some(w) &&
    @execution.checked_preparation_add_product(
      0L,
      value.owned_utf16_units,
      count,
    )
    is Some(t) &&
    @execution.checked_preparation_add_product(
      0L,
      value.owned_wire_bytes,
      count,
    )
    is Some(b) else {
    return None
  }
  let units : @execution.PreparationRepresentationUnits = {
    record_headers: h,
    reference_slots: r,
    scalar_words: w,
    owned_utf16_units: t,
    owned_wire_bytes: b,
  }
  guard @execution.preparation_representation_cost(units) is Some(_) else {
    return None
  }
  Some(units)
}
