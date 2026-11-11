///|
/// Complete Parameter-supported admit constructor, excluding its caller's
/// later Parameter constraints and declaration carriers. Same source/Contract
/// remain borrowed; DATA does not admit values or grant preparation capacity.
pub(all) struct ParameterValuePhaseConstructionInventory {
  returned : @shape.CollectionConstructionExtent
  temporary : @shape.CollectionConstructionExtent
  normalization : @canonical.NormalizationConstructionExtent?
  returned_utf16_units : Int64
  temporary_utf16_units : Int64
} derive(Eq, Debug)

///|
pub fn parameter_syntax_value_phase_construction_inventory(
  original : @contract.ParameterSyntax,
  geometry : @decode.SubtreeConstructionGeometry,
  root_path_depth : Int64,
  max_depth : Int,
) -> ParameterValuePhaseConstructionInventory? {
  if root_path_depth < 0L || max_depth < 0 {
    return None
  }
  guard parameter_syntax_value_body_construction_inventory(original, geometry)
    is Some(body) else {
    return None
  }
  value_phase_construction_inventory(body, geometry, root_path_depth, max_depth)
}

///|
/// The same existing non-reference Value constructor phase, retaining its
/// supplied original checked Contract. Geometry is bounded constructor DATA,
/// not evidence that a value has that type or permission to admit a value.
/// This entry adds no Parameter reader, syntax or declaration construction.
pub fn contract_value_phase_construction_inventory(
  original : @contract.Contract,
  geometry : @decode.SubtreeConstructionGeometry,
  root_path_depth : Int64,
  max_depth : Int,
) -> ParameterValuePhaseConstructionInventory? {
  if root_path_depth < 0L || max_depth < 0 {
    return None
  }
  guard contract_value_body_construction_inventory(original, geometry)
    is Some(body) else {
    return None
  }
  value_phase_construction_inventory(body, geometry, root_path_depth, max_depth)
}

///|
fn value_phase_construction_inventory(
  body : ParameterValueBodyConstructionInventory,
  geometry : @decode.SubtreeConstructionGeometry,
  root_path_depth : Int64,
  max_depth : Int,
) -> ParameterValuePhaseConstructionInventory? {
  // CheckedValue1H2R. Its Value/containers/backing were expanded once by
  // the same body owner and are retained, not recomputed or duplicated here.
  let checked : @shape.CollectionConstructionExtent = {
    record_headers: 1L,
    reference_slots: 2L,
    scalar_words: 0L,
  }
  guard @shape.add_collection_construction_extents(body.value_extent, checked)
    is Some(returned) else {
    return None
  }
  // TypedAdmission/Budget/root+value Options/start/polls/usage/admit wrappers
  //10H17R17W; current scalar/UTF8/count/calendar/int/Decimal/enum families
  //25H4R50W; typed refusal/wrapper/optional-span5H6R6W; builder/field Options
  //3H3R3W. Distinct alternatives co-count, never one allowance per Value.
  // Calendar helpers own Date's4 and Timestamp's two12-element scalar vectors.
  let controls : @shape.CollectionConstructionInventory = {
    records: 43L,
    record_references: 30L,
    record_words: 76L,
    reference_arrays: 0L,
    reference_items: 0L,
    scalar_arrays: 3L,
    scalar_items: 28L,
    maps: 0L,
    map_entries: 0L,
  }
  let relative = Int64::min(
    geometry.nodes.to_int64(),
    max_depth.to_int64() + 1L,
  )
  guard @counts.checked_nonnegative_add_product(root_path_depth, relative, 1L)
    is Some(depth) &&
    @counts.checked_nonnegative_add_product(depth, 1L, 1L) is Some(depth) &&
    @decode.cursor_path_construction_extent(depth) is Some(path) &&
    @shape.collection_construction_extent(controls) is Some(controls) &&
    @shape.add_collection_construction_extents(body.traversal_extent, controls)
    is Some(temporary) &&
    @shape.add_collection_construction_extents(temporary, body.decimal_scratch)
    is Some(temporary) &&
    @shape.add_collection_construction_extents(
      temporary,
      @decode.indexed_child_construction_extent(),
    )
    is Some(temporary) &&
    @shape.add_collection_construction_extents(
      temporary,
      @decode.indexed_field_construction_extent(),
    )
    is Some(temporary) &&
    @shape.add_collection_construction_extents(temporary, path)
    is Some(temporary) &&
    @shape.add_collection_construction_extents(temporary, path)
    is Some(temporary) else {
    return None
  }
  // Two paths can coexist during original key-issue projection. Original
  // default text is borrowed; only actual Decimal output/builder owns text.
  Some({
    returned,
    temporary,
    normalization: body.key_normalization,
    returned_utf16_units: body.owned_value_utf16_units,
    temporary_utf16_units: body.owned_decimal_scratch_utf16_units,
  })
}
