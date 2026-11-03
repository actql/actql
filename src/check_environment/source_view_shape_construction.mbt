///|
// SAME interpreter frame for whole SourceViews and selected acquisition or
// resource-identity subrules. This is factored from view_construction, not a
// second validator, generated grammar or independent control surcharge.
fn source_view_shape_frame_construction(
  nodes : Int64,
  fields : Int64,
  items : Int64,
  path : Int64,
  active : Bool,
) -> @shape.CollectionConstructionExtent {
  let child = @decode.indexed_child_construction_extent()
  let field = @decode.indexed_field_construction_extent()
  // <=2N pending Visit/Next carriers, original Cursors/Some, stack backing,
  // one current object seen-Map and one unique text-array seen-Map. Generated
  // uniqueItems applies only to text leaves, not nested unique-array stacks.
  // Fixed14H10R14W = budget1/0/1, scalar outcomes6/2/9, typed stop7/8/4.
  // Scalar DecodeIssue can construct the original nodes+outer-depth ancestry.
  @shape.collection_construction_extent({
    records: 14L +
    3L * nodes +
    path +
    child.record_headers +
    field.record_headers,
    record_references: 10L +
    6L * nodes +
    path +
    child.reference_slots +
    field.reference_slots,
    record_words: 14L +
    3L * nodes +
    path +
    child.scalar_words +
    field.scalar_words,
    reference_arrays: 2L,
    reference_items: 2L * nodes + path,
    scalar_arrays: 0L,
    scalar_items: 0L,
    maps: if active {
      2L
    } else {
      0L
    },
    map_entries: fields + items,
  }).unwrap()
}

///|
/// One existing shape-check invocation. Both acquisition and resource identity
/// checks construct the WHOLE original generated SourceView rule before selecting
/// their subrule. Its generated constructor inventory stays the single source.
/// Borrowed cursor backing and literal Strings are excluded; no shape is checked.
pub fn source_view_shape_validation_construction_extent(
  nodes : Int,
  max_fields : Int,
  max_items : Int,
  outer_depth : Int,
) -> @shape.CollectionConstructionExtent? {
  if nodes < 1 ||
    max_fields < 0 ||
    max_fields > nodes ||
    max_items < 0 ||
    max_items > nodes ||
    outer_depth < 0 {
    return None
  }
  @shape.add_collection_construction_extents(
    source_view_shape_frame_construction(
      nodes.to_int64(),
      max_fields.to_int64(),
      max_items.to_int64(),
      nodes.to_int64() + outer_depth.to_int64(),
      true,
    ),
    source_view_rule_construction(),
  )
}
