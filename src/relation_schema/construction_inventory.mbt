///|
/// Original unqualified field assembly used by admitted Carrier declarations.
/// Children are already checked and borrowed; this DATA is not type admission.
pub(all) struct SchemaConstructionInventory {
  retained : @shape.CollectionConstructionExtent
  scratch : @shape.CollectionConstructionExtent
  scratch_utf16_units : Int64
} derive(Eq, Debug)

///|
pub fn unqualified_presence_construction_inventory(
  fields : Int,
  max_name_utf16_units : Int,
) -> SchemaConstructionInventory? {
  if fields < 0 || max_name_utf16_units < 0 {
    return None
  }
  let f = fields.to_int64()
  // Scoped Entry+Field2F/4F/F, Schema+representation2/2/3.
  // Co-count the alternative ordinary Object result, never its child bodies.
  // Outer output/flat arrays and tuple alternatives coexist during assembly.
  // Per-name object_contract returns before the final all-field assembler;
  // use that same owner's larger F envelope (one slot covers invalid/empty).
  let one = @contract.object_construction_inventory(
    Int::max(1, fields),
    max_name_utf16_units,
  ).unwrap()
  let frame = @shape.collection_construction_extent({
    records: 18L + 2L * f,
    record_references: 12L + 4L * f,
    record_words: 12L + f,
    reference_arrays: 3L,
    reference_items: 3L * f,
    scalar_arrays: 0L,
    scalar_items: 0L,
    maps: 1L,
    map_entries: f,
  }).unwrap()
  Some({
    retained: unqualified_presence_retained_extent(fields, 1).unwrap(),
    scratch: @shape.add_collection_construction_extents(
      frame,
      @shape.add_collection_construction_extents(one.retained, one.scratch).unwrap(),
    ).unwrap(),
    scratch_utf16_units: one.scratch_utf16_units,
  })
}

///|
pub fn unqualified_presence_retained_extent(
  fields : Int,
  instances : Int,
) -> @shape.CollectionConstructionExtent? {
  if fields < 0 || instances < 0 {
    return None
  }
  let f = fields.to_int64()
  let i = instances.to_int64()
  // Schema flags/name_bytes use3W; its Scoped/Flat payload tag uses1W.
  let scoped = @shape.collection_construction_extent({
    records: 2L * i + 2L * f,
    record_references: 2L * i + 4L * f,
    record_words: 4L * i + f,
    reference_arrays: i,
    reference_items: f,
    scalar_arrays: 0L,
    scalar_items: 0L,
    maps: 0L,
    map_entries: 0L,
  }).unwrap()
  @shape.add_collection_construction_extents(
    scoped,
    @contract.object_retained_construction_extent(fields, instances).unwrap(),
  )
}

///|
/// O(1) wrapper around the original non-null Object; no field copies.
pub fn from_object_construction_extent(
  instances : Int,
) -> @shape.CollectionConstructionExtent? {
  if instances < 0 {
    return None
  }
  let i = instances.to_int64()
  Some({
    record_headers: 2L * i,
    reference_slots: 3L * i,
    scalar_words: 4L * i,
  })
}

///|
/// The SAME reference_name spelling constructor, without constructing a String
/// just to quote it. Unqualified names borrow text; qualification adds its
/// original prefix and one transient String before the caller's charge returns.
pub fn reference_name_construction_extent(
  name : FieldName,
) -> SchemaConstructionInventory {
  let (prefix, text) = reference_parts(name)
  {
    retained: { record_headers: 0L, reference_slots: 0L, scalar_words: 0L, },
    scratch: {
      record_headers: if prefix == "" {
        0L
      } else {
        1L
      },
      reference_slots: 0L,
      scalar_words: 0L,
    },
    scratch_utf16_units: if prefix == "" {
      0L
    } else {
      prefix.length().to_int64() + text.length().to_int64()
    },
  }
}
