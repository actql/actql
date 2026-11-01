///|
/// Quantities of one original declaration, never a type verdict or grant.
/// Default geometry refers only to that declaration's actual default, while
/// metadata_fields distinguishes actual object width from other/absent kinds.
pub(all) struct DeclarationReadConstructionFacts {
  type_syntax : @contract.ParameterReadConstructionGeometry
  default_value : @decode.SubtreeConstructionGeometry?
  metadata_fields : Int?
} derive(Eq, Debug)

///|
priv struct DeclarationReadConstruction {
  entries : Array[DeclarationReadConstructionFacts?]
  work : Int64?
}

///|
/// Observe the same Header's original names in their existing order. The
/// caller funds the complete fact array/Cursor stack before entry. No name,
/// non-null, type, metadata or default admission is performed. Cached repeats
/// return the SAME cumulative metadata work, not a fresh consumption claim.
pub fn observe_declaration_read_construction(
  original : DeclarationReadInput,
) -> Int64? {
  guard original.state is ReadingDeclaration(body) &&
    body.index == 0 &&
    body.syntax is None else {
    return None
  }
  if body.construction is Some(completed) {
    return completed.work
  }
  let entries : Array[DeclarationReadConstructionFacts?] = []
  let mut used = 0L
  for name in body.names {
    // One actual original-name selection and Map lookup metadata observation.
    used += 2L
    let cursor = @decode.lookup(body.object, name).unwrap()
    let sources = @contract.observe_parameter_read_construction_sources(cursor)
    used += sources.work
    let default_value = match sources.default_value {
      None => None
      Some(cursor) => {
        let geometry = @decode.observe_subtree_construction_geometry(cursor)
        used += geometry.work
        Some(geometry)
      }
    }
    let metadata_fields = match sources.metadata {
      None => None
      Some(cursor) => {
        used += 1L
        @decode.object_length(cursor)
      }
    }
    entries.push(
      Some({ type_syntax: sources.geometry, default_value, metadata_fields, }),
    )
  }
  let work = Some(used)
  body.construction = Some({ entries, work, })
  work
}

///|
/// Same retained work observation; missing is not manufactured as zero.
pub fn declaration_read_construction_work(
  original : DeclarationReadInput,
) -> Int64? {
  match original.state {
    ReadingDeclaration(body) =>
      match body.construction {
        None => None
        Some(completed) => completed.work
      }
    _ => None
  }
}

///|
/// Same retained facts/Some for the actual current declaration. No caller
/// ordinal, equal wrapper, Source path lookup or copied record is consumed.
pub fn declaration_read_current_construction(
  original : DeclarationReadInput,
) -> DeclarationReadConstructionFacts? {
  match original.state {
    ReadingDeclaration(body) =>
      match body.construction {
        None => None
        Some(completed) => completed.entries[body.index]
      }
    _ => None
  }
}

///|
pub(all) struct DeclarationReadConstructionInventory {
  retained : @shape.CollectionConstructionExtent
  temporary : @shape.CollectionConstructionExtent
} derive(Eq, Debug)

///|
/// Selected subtree nodes bound the pending original-Cursor stack, never wire
/// bytes or an adjacent Program. Actual Header width bounds the retained fact
/// vector. The Source/type/default bodies stay borrowed at their original owner.
pub fn declaration_read_construction_inventory(
  nodes : Int,
  declarations : Int,
) -> DeclarationReadConstructionInventory? {
  if nodes < 1 || declarations < 1 || declarations >= nodes {
    return None
  }
  let n = declarations.to_int64()
  // Per declaration: Fact3R, TypeGeometry9W, DefaultGeometry11W,
  // default Some1R1W, metadata count Some2W, fact Some1R1W:6H5R24W.
  // Outer array/work holder2R, original body Some1R1W and work Some2W
  // add3H3R3W before the common Array construction backing.
  let output : @shape.CollectionConstructionInventory = {
    records: 6L * n + 3L,
    record_references: 5L * n + 3L,
    record_words: 24L * n + 3L,
    reference_arrays: 1L,
    reference_items: n,
    scalar_arrays: 0L,
    scalar_items: 0L,
    maps: 0L,
    map_entries: 0L,
  }
  let m = nodes.to_int64()
  let walk : @shape.CollectionConstructionInventory = {
    records: m,
    record_references: 2L * m,
    record_words: m,
    reference_arrays: 1L,
    reference_items: m,
    scalar_arrays: 0L,
    scalar_items: 0L,
    maps: 0L,
    map_entries: 0L,
  }
  // Existing lookup4H4R4W and field5H7R3W; three current Cursor/Some
  // pairs6H9R6W; two scalar meters2H6W; sources1H3R1W; spine tuple1H2W.
  // Their output geometries/work Some are retained above. The spend Result
  // and its optional original outcome add2H1R2W after that walk returns.
  let controls : @shape.CollectionConstructionExtent = {
    record_headers: 21L,
    reference_slots: 24L,
    scalar_words: 24L,
  }
  guard @shape.collection_construction_extent(output) is Some(retained) &&
    @shape.collection_construction_extent(walk) is Some(temporary) &&
    @shape.add_collection_construction_extents(temporary, controls)
    is Some(temporary) else {
    return None
  }
  Some({ retained, temporary, })
}
