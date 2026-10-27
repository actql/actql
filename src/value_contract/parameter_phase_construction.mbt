///|
/// Complete existing ParameterSyntax construction, excluding the caller's
/// attachment/outer issue carriers and pinned builtin sorting frames. Quantity
/// DATA never admits syntax, grants capacity or changes original semantic limits.
pub(all) struct ParameterReadPhaseConstructionInventory {
  returned : @shape.CollectionConstructionExtent
  temporary : @shape.CollectionConstructionExtent
  normalization : @canonical.NormalizationConstructionExtent?
  sort_fields : Int
} derive(Eq, Debug)

///|
pub fn parameter_read_phase_construction_inventory(
  geometry : ParameterReadConstructionGeometry,
  root_path_depth : Int64,
  limits : Limits,
) -> ParameterReadPhaseConstructionInventory? {
  let g = geometry
  if root_path_depth < 0L ||
    g.types < 1 ||
    limits.max_nodes < 0 ||
    limits.max_depth < 0 ||
    limits.max_text_bytes < 0 {
    return None
  }
  guard parameter_read_construction_inventory(g) is Some(output) &&
    @shape.collection_construction_extent(output) is Some(returned) else {
    return None
  }
  // Syntax3R; its two optional original default/meta Cursors4R2W and
  // their Some2R2W. The caller's own syntax attachment is a separate owner.
  let syntax : @shape.CollectionConstructionExtent = {
    record_headers: 5L,
    reference_slots: 9L,
    scalar_words: 4L,
  }
  guard @shape.add_collection_construction_extents(returned, syntax)
    is Some(returned) else {
    return None
  }
  let t = g.types.to_int64()
  let f = g.fields.to_int64()
  let m = g.max_view_fields.to_int64()
  // SAME key-check selector for current type's <=7 allowed fields and a
  // possible field-name refusal. No copied small/wide-path threshold/table.
  guard @shape.object_key_construction_counts(
      g.max_view_fields,
      0,
      Int::max(g.max_view_fields, 7),
    )
    is Some(keys) else {
    return None
  }
  let frames = 2L * t + 2L
  let scratch : @shape.CollectionConstructionInventory = {
    // Pending/current ParameterWork2R3W; detached child Cursor2R1W;
    // actual key-map input tuples borrow names and hold Unit (no Value body).
    records: frames + t + keys.pairs,
    record_references: 2L * frames + 2L * t + keys.pairs,
    record_words: 3L * frames + t,
    // work, values, object names, extras/allowed, closed keys, failure filter,
    // empty required vector and the actual selected key-check pair vectors.
    reference_arrays: 7L + g.objects.to_int64() + keys.pair_arrays.to_int64(),
    reference_items: 3L * t + f + 11L + 2L * m + keys.pairs,
    // Original nonblank's14 fixed whitespace scalars, one live call at a time.
    scalar_arrays: 1L,
    scalar_items: 14L,
    maps: 3L + keys.maps.to_int64(),
    map_entries: 3L * m + keys.map_entries,
  }
  // Budget1H4W; three ObjectViews3H6R; four current lookup families16H16R16W;
  // eleven possible scalar/required Result locations11H11R22W; Decode/Contract
  // refusal chain8H10R12W; six projection/key/filter closures6H1R.
  // These disjoint current alternatives are co-counted, never one per node.
  let controls : @shape.CollectionConstructionExtent = {
    record_headers: 45L,
    reference_slots: 44L,
    scalar_words: 54L,
  }
  guard @shape.collection_construction_extent(scratch) is Some(temporary) &&
    @shape.add_collection_construction_extents(temporary, controls)
    is Some(temporary) else {
    return None
  }
  // Each nested object field adds two original path edges, array item one.
  // Current enum/field/required-key failures add at most two. Two locations
  // can coexist while an original key charge is projected to its key span.
  let relative = Int64::min(t, limits.max_depth.to_int64() + 1L)
  guard @counts.checked_nonnegative_add_product(root_path_depth, relative, 2L)
    is Some(depth) &&
    @counts.checked_nonnegative_add_product(depth, 2L, 1L) is Some(depth) &&
    @decode.cursor_path_construction_extent(depth) is Some(path) &&
    @shape.add_collection_construction_extents(temporary, path)
    is Some(temporary) &&
    @shape.add_collection_construction_extents(temporary, path)
    is Some(temporary) else {
    return None
  }
  let normalization = if g.max_identifier_units == 0 {
    None
  } else {
    @canonical.nfc_lf_construction_extent(
      Int::min(g.max_identifier_units, limits.max_text_bytes),
    )
  }
  if g.max_identifier_units > 0 && normalization is None {
    return None
  }
  Some({
    returned,
    temporary,
    normalization,
    sort_fields: if g.objects == 0 {
      0
    } else {
      g.max_view_fields
    },
  })
}
