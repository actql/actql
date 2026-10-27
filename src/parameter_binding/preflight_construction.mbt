///|
/// Constructor quantities of the SAME declaration preflight, including its
/// complete first-refusal location. Input/default/meta are not reconstructed.
/// Type/default/metadata body construction is a separate next phase.
pub(all) struct DeclarationPreflightConstructionInventory {
  traversal : @shape.CollectionConstructionExtent
  refusal : @shape.CollectionConstructionExtent
  key_normalization : @canonical.NormalizationConstructionExtent?
} derive(Eq, Debug)

///|
/// Invalid original fixed limits and absent declarations need no input walk.
/// Only construction metadata is observed; the SAME semantic entry still
/// issues its original refusal and partial source usage after reservation.
pub fn observe_declaration_preflight_construction(
  root : @decode.Cursor?,
  limits : DeclarationLimits,
) -> (@decode.SubtreeConstructionGeometry?, Int, Int64) {
  if declaration_limits_invalid(limits) {
    return (None, 0, 0L)
  }
  match root {
    None => (None, 0, 0L)
    Some(original) => {
      let geometry = @decode.observe_subtree_construction_geometry(original)
      let (depth, ancestry) = @decode.observe_cursor_path_depth(original)
      (Some(geometry), depth, geometry.work + ancestry)
    }
  }
}

///|
pub fn declaration_preflight_construction_inventory(
  geometry : @decode.SubtreeConstructionGeometry,
  root_path_depth : Int,
  limits : DeclarationLimits,
) -> DeclarationPreflightConstructionInventory? {
  let g = geometry
  if root_path_depth < 0 ||
    g.nodes < 1 ||
    g.arrays < 0 ||
    g.objects < 0 ||
    g.array_items < 0 ||
    g.fields < 0 ||
    g.max_object_fields < 0 ||
    g.max_object_fields > g.fields ||
    g.max_key_utf16 < 0 {
    return None
  }
  // Child counts are charged BEFORE constructing indexed children. Actual
  // pending nodes cannot exceed the SAME original semantic node budget.
  let n = Int::min(g.nodes, Int::max(0, limits.max_nodes)).to_int64()
  // Pending (Cursor,depth) pairs plus their detached child Cursors own
  //2H3R2W per actual node. One current scalar ValueView adds1H1R2W.
  // The fixed Budget is in the entering driver packet, including absent input.
  // Original indexed children replace all detached container views. Current
  // indexed-read carriers are added from their SAME Decode owner below.
  let traversal : @shape.CollectionConstructionInventory = {
    records: 2L * n + 1L,
    record_references: 3L * n + 1L,
    record_words: 2L * n + 2L,
    reference_arrays: 1L,
    reference_items: n,
    scalar_arrays: 0L,
    scalar_items: 0L,
    maps: 0L,
    map_entries: 0L,
  }
  let declared_depth = Int::max(0, limits.max_depth).to_int64() + 1L
  let relative_depth = Int64::min(g.nodes.to_int64(), declared_depth)
  guard @decode.cursor_path_construction_extent(
      root_path_depth.to_int64() + relative_depth,
    )
    is Some(path) else {
    return None
  }
  let failure = parameter_issue_construction_extent()
  guard @shape.collection_construction_extent(traversal) is Some(traversal) &&
    @shape.add_collection_construction_extents(
      traversal,
      @decode.indexed_child_construction_extent(),
    )
    is Some(traversal) &&
    @shape.add_collection_construction_extents(
      traversal,
      @decode.indexed_field_construction_extent(),
    )
    is Some(traversal) &&
    @shape.add_collection_construction_extents(failure, path) is Some(refusal) else {
    return None
  }
  let key_normalization = if g.fields == 0 || n < 2L {
    None
  } else {
    guard @canonical.nfc_lf_construction_extent(
        Int::min(g.max_key_utf16, Int::max(0, limits.max_text_bytes)),
      )
      is Some(value) else {
      return None
    }
    Some(value)
  }
  Some({ traversal, refusal, key_normalization, })
}
