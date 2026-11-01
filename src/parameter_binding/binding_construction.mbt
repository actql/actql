///|
/// Completed construction metadata of one original selected binding, not a
/// type verdict, caller proof, capacity claim or substituted declaration.
pub(all) struct BindingReadConstructionFacts {
  declaration : Declaration
  selected : @decode.Cursor?
  provided : Bool
  geometry : @decode.SubtreeConstructionGeometry?
  depth : Int
}

///|
priv struct BindingReadConstruction {
  entries : Array[BindingReadConstructionFacts?]
  work : Int64?
}

///|
/// Bound one whole original inventory walk before entry, without selecting or
/// walking any supplied/default value. All declarations came from one admitted
/// original tree; each selected geometry+ancestry takes at most4 tree visits.
/// This work envelope allocates no memory proportional to its wide scalar.
pub fn binding_read_construction_maximum_work(
  original : BindingReadInput,
) -> Int64? {
  guard original.state is ReadingBinding(body) &&
    body.index == 0 &&
    body.phase == BindingSelection else {
    return None
  }
  let count = original.declarations.entries.length().to_int64()
  let declared = @decode.admission_usage(
      original.declarations.entries[0].source,
    ).nodes
  let supplied = match original.supplied {
    None => 0
    Some(cursor) => @decode.admission_usage(cursor).nodes
  }
  @counts.checked_nonnegative_add_product(
    2L * count,
    Int::max(declared, supplied).to_int64(),
    4L * count,
  )
}

///|
/// Fund the complete actual fact array before this walk. The SAME private
/// source selection feeds the later semantic step, so no second Map lookup,
/// type walk or default admission is performed. Cached repeats return SAME
/// work/Some; the original Resource phase may only spend that work once.
pub fn observe_binding_read_construction(original : BindingReadInput) -> Int64? {
  guard original.state is ReadingBinding(body) &&
    body.index == 0 &&
    body.phase == BindingSelection else {
    return None
  }
  if body.construction is Some(completed) {
    return completed.work
  }
  let entries : Array[BindingReadConstructionFacts?] = []
  let mut used = 0L
  for declaration in original.declarations.entries {
    used += 2L
    let (provided, selected) = select_binding_source(body.object, declaration)
    let (geometry, depth) = match selected {
      None => (None, 0)
      Some(cursor) => {
        let geometry = @decode.observe_subtree_construction_geometry(cursor)
        let (depth, ancestry) = @decode.observe_cursor_path_depth(cursor)
        used += geometry.work + ancestry
        (Some(geometry), depth)
      }
    }
    entries.push(Some({ declaration, selected, provided, geometry, depth, }))
  }
  let work = Some(used)
  body.construction = Some({ entries, work, })
  work
}

///|
pub fn binding_read_construction_work(original : BindingReadInput) -> Int64? {
  match original.state {
    ReadingBinding(body) =>
      match body.construction {
        None => None
        Some(completed) => completed.work
      }
    _ => None
  }
}

///|
/// SAME stored fact/Some at the actual reader index. No caller index, name,
/// copied geometry or equal declaration can select another entry's backing.
pub fn binding_read_current_construction(
  original : BindingReadInput,
) -> BindingReadConstructionFacts? {
  match original.state {
    ReadingBinding(body) =>
      match body.construction {
        None => None
        Some(completed) => completed.entries[body.index]
      }
    _ => None
  }
}

///|
pub(all) struct BindingReadConstructionInventory {
  retained : @shape.CollectionConstructionExtent
  temporary : @shape.CollectionConstructionExtent
} derive(Eq, Debug)

///|
/// One fact vector for actual original declaration width. Each entry keeps
/// Fact3R2W, fact/geometry Options2R2W, Geometry11W and at most one newly
/// selected Cursor+Some3R2W:6H8R17W. Original default bodies stay borrowed.
pub fn binding_read_construction_inventory(
  original : BindingReadInput,
) -> BindingReadConstructionInventory? {
  guard original.state is ReadingBinding(body) &&
    body.index == 0 &&
    body.phase == BindingSelection else {
    return None
  }
  let count = original.declarations.entries.length().to_int64()
  let output : @shape.CollectionConstructionInventory = {
    records: 6L * count + 3L,
    record_references: 8L * count + 3L,
    record_words: 17L * count + 3L,
    reference_arrays: 1L,
    reference_items: count,
    scalar_arrays: 0L,
    scalar_items: 0L,
    maps: 0L,
    map_entries: 0L,
  }
  // Lookup4H4R4W, additional selected Some1H1R1W, selection and original
  // geometry/depth tuples2H2R2W, spine/ancestry tuples2H4W, work outcome
  // selection and optional spend2H1R2W. Co-count original retained lookup
  // alternatives too; this fixed envelope has no subtree Cursor stack.
  let temporary : @shape.CollectionConstructionExtent = {
    record_headers: 11L,
    reference_slots: 8L,
    scalar_words: 13L,
  }
  guard @shape.collection_construction_extent(output) is Some(retained) else {
    return None
  }
  Some({ retained, temporary, })
}

///|
/// One selection's actual output: the stored original declaration Option or
/// one missing-array append. Input selection already belongs to the same fact.
/// Final usage/result carriers are added only at the actual last entry.
pub fn binding_selection_construction_extent(
  original : BindingReadInput,
) -> @shape.CollectionConstructionExtent? {
  guard original.state is ReadingBinding(body) &&
    body.phase == BindingSelection &&
    body.construction is Some(completed) &&
    completed.entries[body.index] is Some(current) else {
    return None
  }
  let selected : @shape.CollectionConstructionExtent = match current.selected {
    None => { record_headers: 0L, reference_slots: 3L, scalar_words: 0L, }
    Some(_) => { record_headers: 1L, reference_slots: 1L, scalar_words: 1L, }
  }
  if current.selected is None &&
    body.index + 1 == original.declarations.entries.length() {
    @shape.add_collection_construction_extents(
      selected,
      binding_completion_construction_extent(),
    )
  } else {
    Some(selected)
  }
}

///|
// Final usage tuple2W/BoundValues or MissingNames3R/Ready or Needs1R1W/
// Ok1R1W/completed state1R1W. Private partial arrays never escape as Ready.
fn binding_completion_construction_extent() -> @shape.CollectionConstructionExtent {
  { record_headers: 5L, reference_slots: 6L, scalar_words: 5L, }
}
