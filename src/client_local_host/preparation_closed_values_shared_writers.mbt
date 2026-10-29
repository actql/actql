///|
/// Shared encoder dependency. Hashing structurally dominates measuring/text
/// writers; the latter also require their own JS builder old/new text owners.
fn closed_values_writer_layout(
  nodes : Int,
  depth : Int,
  count : Int,
  material_count : Int,
  material_bytes : Int,
) -> @execution.PreparationRepresentationUnits? {
  if count < 0 ||
    material_count < 0 ||
    material_count > count ||
    material_bytes < 0 {
    return None
  }
  guard @encode.hash_writer_construction_inventory(nodes, depth) is Some(w) else {
    return None
  }
  let c = count.to_int64()
  let m = material_count.to_int64()
  let b = material_bytes.to_int64()
  // Count is internal today, but preserve checked arithmetic if reused.
  guard @execution.checked_preparation_add_product(
      4L * m,
      w.record_headers,
      c + 1L,
    )
    is Some(h_plus) &&
    @execution.checked_preparation_add_product(
      2L * m,
      w.reference_slots,
      c + 1L,
    )
    is Some(r_plus) &&
    @execution.checked_preparation_add_product(m, w.scalar_words, c + 1L)
    is Some(s_plus) &&
    @execution.checked_preparation_add_product(
      2L * m * b,
      w.owned_utf16_units,
      c + 1L,
    )
    is Some(t_plus) &&
    @execution.checked_preparation_add_product(0L, w.owned_wire_bytes, c + 1L)
    is Some(b_plus) else {
    return None
  }
  let output : @execution.PreparationRepresentationUnits = {
    record_headers: h_plus - w.record_headers,
    reference_slots: r_plus - w.reference_slots,
    scalar_words: s_plus - w.scalar_words,
    owned_utf16_units: t_plus - w.owned_utf16_units,
    owned_wire_bytes: b_plus - w.owned_wire_bytes,
  }
  guard @execution.preparation_representation_cost(output) is Some(_) else {
    return None
  }
  Some(output)
}
