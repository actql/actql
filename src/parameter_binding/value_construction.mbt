///|
/// The original Value step's three sequential temporary families. The caller
/// prices their maximum only after each synchronous prior family has returned.
/// Retained declaration/default output coexists with every selected family.
pub(all) struct DeclarationValueConstructionInventory {
  returned : @shape.CollectionConstructionExtent
  metadata : @shape.CollectionConstructionExtent
  constraints : @shape.CollectionConstructionExtent
  value : @value.ParameterValuePhaseConstructionInventory?
} derive(Eq, Debug)

///|
/// Select ONLY this original reader's current completed syntax/fact. No
/// caller ordinal, equal schema or precision hint enters the construction.
pub fn declaration_value_construction_inventory(
  original : DeclarationReadInput,
  root_path_depth : Int,
) -> DeclarationValueConstructionInventory? {
  guard root_path_depth >= 0 &&
    original.state is ReadingDeclaration(body) &&
    body.syntax is Some(syntax) &&
    body.construction is Some(facts) &&
    facts.entries[body.index] is Some(current) else {
    return None
  }
  let value = match (syntax.default_value, current.default_value) {
    (None, None) => None
    (Some(_), Some(geometry)) => {
      guard @value.parameter_syntax_value_phase_construction_inventory(
          syntax,
          geometry,
          root_path_depth.to_int64() + 2L,
          original.limits.max_depth,
        )
        is Some(value) else {
        return None
      }
      // check_value receives a fresh Value Limits while Value admission is
      // active. Its failure also enters the original outer Parameter carriers.
      // These SAME caller-owned records must coexist in this family too.
      let limits : @shape.CollectionConstructionExtent = {
        record_headers: 1L,
        reference_slots: 0L,
        scalar_words: 3L,
      }
      guard @shape.add_collection_construction_extents(
          limits,
          parameter_issue_construction_extent(),
        )
        is Some(caller) &&
        @shape.add_collection_construction_extents(value.temporary, caller)
        is Some(temporary) else {
        return None
      }
      Some({ ..value, temporary, })
    }
    _ => return None
  }
  // Declaration7R retains SAME original Syntax; default Some1R1W; final Declarations2R/Ok1R1W/state1R1W.
  // Three incremental entry slots extend Header's SAME growing entries Array.
  // Next original Cursor+Some2H3R2W can remain in that Header/next declaration.
  let declaration : @shape.CollectionConstructionExtent = {
    record_headers: 7L,
    reference_slots: 18L,
    scalar_words: 5L,
  }
  let returned = match value {
    None => declaration
    Some(value) => {
      guard @shape.add_collection_construction_extents(
          declaration,
          value.returned,
        )
        is Some(value) else {
        return None
      }
      value
    }
  }
  let fields = current.metadata_fields.unwrap_or(0)
  guard @shape.object_key_construction_counts(fields, 0, fields) is Some(keys) else {
    return None
  }
  // Original metadata opens its Map and names before empty/reserved refusal.
  // A reserved-key failure additionally owns filter/closed keys/empty required
  // and the SAME selected key-check pair arrays/maps, with borrowed names.
  let metadata : @shape.CollectionConstructionInventory = {
    records: 12L + keys.pairs,
    record_references: 12L + keys.pairs,
    record_words: 12L,
    reference_arrays: if syntax.metadata is Some(_) {
      4L + keys.pair_arrays.to_int64()
    } else {
      0L
    },
    reference_items: 3L * fields.to_int64() + keys.pairs,
    scalar_arrays: 0L,
    scalar_items: 0L,
    maps: (if current.metadata_fields is Some(_) { 1L } else { 0L }) +
    keys.maps.to_int64(),
    map_entries: fields.to_int64() + keys.map_entries,
  }
  let n = match current.default_value {
    None => 0L
    Some(g) => g.nodes.to_int64()
  }
  // Metadata adds a child key; default constraints can fail at a full original
  // nested path. The two paths cover key-span/error projection coexistence.
  let relative = Int64::max(
    3L,
    Int64::min(n, original.limits.max_depth.to_int64() + 1L) + 3L,
  )
  guard @decode.cursor_path_construction_extent(
      root_path_depth.to_int64() + relative,
    )
    is Some(path) &&
    @shape.collection_construction_extent(metadata) is Some(metadata) &&
    @shape.add_collection_construction_extents(
      metadata,
      parameter_issue_construction_extent(),
    )
    is Some(metadata) &&
    @shape.add_collection_construction_extents(metadata, path) is Some(metadata) &&
    parameter_constraints_construction_extent(current.default_value, path)
    is Some(constraints) else {
    return None
  }
  Some({ returned, metadata, constraints, value, })
}
