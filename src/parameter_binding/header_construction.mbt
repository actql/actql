///|
/// Actual Header constructor storage plus its selected name-sort width. The
/// sorting algorithm belongs to its existing pinned builtin owner. These are
/// DATA quantities, never a substitute for the Header's original typed result.
pub(all) struct DeclarationHeaderConstructionInventory {
  storage : @shape.CollectionConstructionExtent
  sort_fields : Int
} derive(Eq, Debug)

///|
// Sole original empty/count guard, shared with its constructor selection.
// The actual Header still issues the original error at its original root.
fn declaration_header_issue(
  count : Int,
  limits : DeclarationLimits,
) -> IssueKind? {
  if count == 0 {
    Some(EmptyDeclarations)
  } else if count > limits.max_parameters {
    Some(ParameterLimit)
  } else {
    None
  }
}

///|
// Same typed Decode/Parameter issue, Abort/Result and outward state carriers.
// Path storage is separate and belongs to Decode. This is not a second rule
// for any error kind, byte tariff, semantic verdict or resource issuer.
fn parameter_issue_construction_extent() -> @shape.CollectionConstructionExtent {
  { record_headers: 5L, reference_slots: 7L, scalar_words: 5L, }
}

///|
/// Open-object Map and name vector are built BEFORE the count guard. Their
/// width is the actual original field count, never min(count,max_parameters).
/// Absent/wrong-kind inputs keep their original outcome, not a guessed shape.
pub fn declaration_header_construction_inventory(
  root : @decode.Cursor?,
  root_path_depth : Int,
  limits : DeclarationLimits,
) -> DeclarationHeaderConstructionInventory? {
  if root_path_depth < 0 {
    return None
  }
  let fields = match root {
    None => None
    Some(original) => @decode.object_length(original)
  }
  let count = fields.unwrap_or(0)
  let sort_fields = if fields is Some(_) &&
    declaration_header_issue(count, limits) is None {
    count
  } else {
    0
  }
  // Reader5R1W; state1R1W; ObjectView2R; object/name Results2R2W;
  // absent Declarations2R/Ok1R1W; scalar issue-selection Some2W. Their
  // disjoint alternative headers are co-counted:8H13R7W. Lookup carriers
  // come from Decode below. Two Arrays are names plus initially empty entries.
  let header : @shape.CollectionConstructionInventory = {
    records: 8L,
    record_references: 13L,
    record_words: 7L,
    reference_arrays: 2L,
    reference_items: count.to_int64(),
    scalar_arrays: 0L,
    scalar_items: 0L,
    maps: if fields is Some(_) {
      1L
    } else {
      0L
    },
    map_entries: count.to_int64(),
  }
  guard @shape.collection_construction_extent(header) is Some(storage) &&
    @shape.add_collection_construction_extents(
      storage,
      @decode.indexed_child_construction_extent(),
    )
    is Some(storage) &&
    @shape.add_collection_construction_extents(
      storage,
      parameter_issue_construction_extent(),
    )
    is Some(storage) &&
    @decode.cursor_path_construction_extent(root_path_depth.to_int64())
    is Some(path) &&
    @shape.add_collection_construction_extents(storage, path) is Some(storage) else {
    return None
  }
  Some({ storage, sort_fields, })
}
