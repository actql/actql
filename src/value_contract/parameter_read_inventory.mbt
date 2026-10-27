///|
/// Quantities of the existing ParameterType/Contract/ParameterRule return
/// family. This is a constructor peak, not a minimum, tariff, grant, physical
/// backing assertion or a retained-after-GC quantity. Source/index/text remain
/// with their original owners. The semantic reader alone admits these types.
pub fn parameter_read_construction_inventory(
  geometry : ParameterReadConstructionGeometry,
) -> @shape.CollectionConstructionInventory? {
  let g = geometry
  if g.types < 0 ||
    g.arrays < 0 ||
    g.objects < 0 ||
    g.fields < 0 ||
    g.enumerants < 0 ||
    g.enumeration_arrays < 0 ||
    g.max_view_fields < 0 ||
    g.max_identifier_units < 0 ||
    g.work < 0L ||
    g.arrays.to_int64() + g.objects.to_int64() > g.types.to_int64() ||
    g.enumeration_arrays > g.types {
    return None
  }
  // One completed type owns ParameterType and Contract plus its original
  // Shape/Rule/constraint alternatives. The maximum six headers cover the
  // object wrappers or both array constraint options; ten references and
  // twelve words conservatively cover the disjoint scalar alternatives too.
  // Object fields own the actual (name,ParameterType) tuple AND Field record;
  // each enum owns its Some/Enumeration wrappers. Referenced input names and
  // enumerant Strings are borrowed, never normalized or copied by this return.
  guard @counts.checked_nonnegative_add_product(0L, g.types.to_int64(), 6L)
    is Some(h) &&
    @counts.checked_nonnegative_add_product(h, g.fields.to_int64(), 2L)
    is Some(h) &&
    @counts.checked_nonnegative_add_product(
      h,
      g.enumeration_arrays.to_int64(),
      2L,
    )
    is Some(h) &&
    @counts.checked_nonnegative_add_product(0L, g.types.to_int64(), 10L)
    is Some(r) &&
    @counts.checked_nonnegative_add_product(r, g.fields.to_int64(), 4L)
    is Some(r) &&
    @counts.checked_nonnegative_add_product(
      r,
      g.enumeration_arrays.to_int64(),
      2L,
    )
    is Some(r) &&
    @counts.checked_nonnegative_add_product(0L, g.types.to_int64(), 12L)
    is Some(w) &&
    @counts.checked_nonnegative_add_product(
      w,
      g.enumeration_arrays.to_int64(),
      1L,
    )
    is Some(w) &&
    @counts.checked_nonnegative_add_product(
      g.enumeration_arrays.to_int64(),
      g.objects.to_int64(),
      2L,
    )
    is Some(arrays) &&
    @counts.checked_nonnegative_add_product(
      g.enumerants.to_int64(),
      g.fields.to_int64(),
      2L,
    )
    is Some(items) else {
    return None
  }
  Some({
    records: h,
    record_references: r,
    record_words: w,
    // ParameterObject retains entries and its Field projection. Each original
    // enum retains its vector. Growth/backing belongs only to @shape's owner.
    reference_arrays: arrays,
    reference_items: items,
    scalar_arrays: 0L,
    scalar_items: 0L,
    maps: 0L,
    map_entries: 0L,
  })
}
