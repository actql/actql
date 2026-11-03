///|
/// Header of this SAME original binding reader. The names vector uses actual
/// retained declarations; supplied closed-object backing uses actual supplied
/// width even when unknown keys refuse. No name/type/Value admission runs here.
pub fn binding_header_construction_extent(
  original : BindingReadInput,
  root_path_depth : Int,
) -> @shape.CollectionConstructionExtent? {
  if root_path_depth < 0 || !(original.state is AwaitingBindingHeader) {
    return None
  }
  // Original reader4R3W/state1R1W, body7R3W/Budget3W, object Some1R1W,
  // names projection closure1R, completed usage2W/result3R/Ready1R1W/
  // Ok1R1W/state1R1W. Empty completion and in-progress Header alternatives
  // coexist in this conservative constructor envelope:11H20R16W. The reader's
  // two added scalars retain actual successful per-value admission maxima.
  // Three Arrays are names plus the same initially empty entries/missing.
  let header : @shape.CollectionConstructionInventory = {
    records: 11L,
    record_references: 20L,
    record_words: 16L,
    reference_arrays: 3L,
    reference_items: original.declarations.entries.length().to_int64(),
    scalar_arrays: 0L,
    scalar_items: 0L,
    maps: 0L,
    map_entries: 0L,
  }
  guard @shape.collection_construction_extent(header) is Some(storage) &&
    @shape.add_collection_construction_extents(
      storage,
      binding_issue_construction_extent(),
    )
    is Some(storage) else {
    return None
  }
  match original.supplied {
    None => Some(storage)
    Some(cursor) => {
      guard @decode.closed_object_construction_extent(
          cursor,
          original.declarations.entries.length(),
          root_path_depth,
        )
        is Some(closed) else {
        return None
      }
      @shape.add_collection_construction_extents(storage, closed)
    }
  }
}

///|
// BindingInput retains original Origin DATA as well as the existing Parameter
// issue. Its own variant tag+Origin require2W; it is not a supplied/default
// inference or another validation layer.
fn binding_issue_origin_construction_extent() -> @shape.CollectionConstructionExtent {
  { record_headers: 1L, reference_slots: 1L, scalar_words: 2L, }
}

///|
fn binding_issue_construction_extent() -> @shape.CollectionConstructionExtent {
  @shape.add_collection_construction_extents(
    parameter_issue_construction_extent(),
    binding_issue_origin_construction_extent(),
  ).unwrap()
}
