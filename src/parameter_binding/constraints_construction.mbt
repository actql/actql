///|
// The constructor table belongs to the existing constraints function. Both
// declaration defaults and provided bindings use this SAME recipe after full
// Value admission; no duplicate contract walk or numeric-constraint law.
fn parameter_constraints_construction_extent(
  geometry : @decode.SubtreeConstructionGeometry?,
  path : @shape.CollectionConstructionExtent,
) -> @shape.CollectionConstructionExtent? {
  let (n, arrays, objects, children, names) = match geometry {
    None => (0L, 0L, 0L, 0L, 0L)
    Some(g) =>
      (
        g.nodes.to_int64(),
        g.arrays.to_int64(),
        g.objects.to_int64(),
        g.array_items.to_int64(),
        g.fields.to_int64(),
      )
  }
  // Original constraints run only after complete Value admission. Thus original
  // typed fields/child copies correspond to the admitted source occurrences.
  // Each work tuple+child Cursor2H4R1W; each ObjectView1H2R. Arrays are work,
  // actual elements copies and actual ParameterFields copies. Maps hold indices.
  // Fixed Limits/results/numeric/duration/next-lookup families11H7R15W,
  // original work-pop Some1H1R1W and elements projection closure1H1R, plus
  // shared Parameter issue carriers5H7R5W are included here.
  // The same successful Value/usage tuple now stays live through constraints:
  // one header, one borrowed CheckedValue reference and two measured scalars.
  let constraints : @shape.CollectionConstructionInventory = {
    records: 2L * n + objects + 19L,
    record_references: 4L * n + 2L * objects + 17L,
    record_words: n + 23L,
    reference_arrays: 1L + arrays + objects,
    reference_items: n + children + names,
    scalar_arrays: 0L,
    scalar_items: 0L,
    maps: objects,
    map_entries: names,
  }
  guard @shape.collection_construction_extent(constraints) is Some(constraints) &&
    @shape.add_collection_construction_extents(constraints, path)
    is Some(constraints) else {
    return None
  }
  @shape.add_collection_construction_extents(constraints, path)
}
