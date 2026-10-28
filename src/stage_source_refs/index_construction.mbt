///|
/// Actual shallow source-index constructor quantities. No declaration value,
/// schema, row, request or name text is scanned, copied or admitted here.
pub(all) struct IndexConstructionGeometry {
  stages : Int
  object_views : Int
  slot_maps : Int
  import_maps : Int
  slots : Int64
  imports : Int64
  max_stage_fields : Int
  inspection_work : Int64
} derive(Eq, Debug)

///|
priv struct IndexQuantityScan {
  mut visits : Int64
}

///|
fn index_quantity_inputs(
  root : @decode.Cursor,
  scan : IndexQuantityScan,
) -> @decode.Cursor {
  scan.visits += 1L
  for i in 0..<@decode.object_length(root).unwrap() {
    scan.visits += 2L
    let (name, value) = @decode.field_at(root, i).unwrap()
    if name == "inputs" {
      return value
    }
  }
  abort("original admitted Stage retains its inputs field")
}

///|
/// The same original minimum work prefix bounds possible Map construction.
/// Omitting later input-field/text costs enlarges the possible prefix, never
/// admits a Source or changes the actual indexer's original error precedence.
pub fn observe_index_construction_geometry(
  source : @stages.Source,
  limits : Limits,
) -> IndexConstructionGeometry {
  let scan : IndexQuantityScan = { visits: 0L, }
  let mut stages = 0
  let mut views = 0
  let mut slot_maps = 0
  let mut import_maps = 0
  let mut slots = 0L
  let mut imports = 0L
  let mut fields = 0
  if !preparation_limits_invalid(limits) {
    scan.visits = 1L
    stages = @stages.stage_count(source)
    if stages <= limits.max_work {
      let mut remaining = limits.max_work - stages
      for i in 0..<stages {
        scan.visits += 1L
        let stage = @stages.stage_at(source, i).unwrap()
        let root = @syntax.stage_body(stage)
        scan.visits += 1L
        fields = Int::max(fields, @decode.object_length(root).unwrap())
        views += 1 // ObjectView is built before the original input charge.
        let declarations = index_quantity_inputs(root, scan)
        scan.visits += 1L
        let n = @decode.object_length(declarations).unwrap()
        if n > remaining {
          break
        }
        remaining -= n
        import_maps += 1 // Empty import Map exists before its count charge.
        scan.visits += 1L
        let count = @syntax.import_count(stage)
        scan.visits += 1L
        if count > remaining {
          break
        }
        remaining -= count
        slot_maps += 1
        slots += n.to_int64()
        imports += count.to_int64()
      }
    }
  }
  {
    stages,
    object_views: views,
    slot_maps,
    import_maps,
    slots,
    imports,
    max_stage_fields: fields,
    inspection_work: scan.visits,
  }
}

///|
/// Six named visits per possible Stage: Stage/root, probe, input width, import
/// count and prefix decision; each indexed field probe adds two. The actual
/// closed Stage owner supplies its field count. No whole-Program/row maximum
/// or independent copied syntax table funds this metadata walk.
pub fn index_construction_inspection_bound(
  source : @stages.Source,
  limits : Limits,
) -> Int64 {
  if preparation_limits_invalid(limits) {
    return 0L
  }
  let n = @stages.stage_count(source)
  if n > limits.max_work {
    return 1L
  }
  1L + n.to_int64() * (6L + 2L * @syntax.stage_closed_field_count().to_int64())
}

///|
/// Fixed scan/result2H9W, Stage Some1H1R1W, three length Some3H6W,
/// and one shared indexed-field frame. The probe returns its Cursor directly,
/// without another Some. No Map or
/// input-sized Array is constructed by inspection. Quotation stays separate.
pub fn index_construction_inspection_extent() -> @shape.CollectionConstructionExtent {
  index_inspection_units
}

///|
let index_inspection_units : @shape.CollectionConstructionExtent = {
  record_headers: 6L +
  @decode.indexed_field_construction_extent().record_headers,
  reference_slots: 1L +
  @decode.indexed_field_construction_extent().reference_slots,
  scalar_words: 16L + @decode.indexed_field_construction_extent().scalar_words,
}

///|
pub fn index_construction_geometry_extent() -> @shape.CollectionConstructionExtent {
  index_geometry_units
}

///|
let index_geometry_units : @shape.CollectionConstructionExtent = {
  record_headers: 1L,
  reference_slots: 0L,
  scalar_words: 8L,
}

///|
/// Source-index containers only. All imported Maps and Stage ObjectViews are
/// conservatively co-counted, not assumed retired after an iteration. Keys,
/// tree/usage/identifier backing stay with the original source owner; retained
/// Slot Cursor wrappers are counted separately per possible entry.
/// Original UTF8 admission controls are included from their scalar owner.
/// VM/quotation frames and the optional observer remain separate.
pub(all) struct IndexConstructionInventory {
  returned : @shape.CollectionConstructionExtent
  temporary : @shape.CollectionConstructionExtent
} derive(Eq, Debug)

///|
pub fn index_construction_inventory(
  g : IndexConstructionGeometry,
  limits : Limits,
) -> IndexConstructionInventory? {
  let zero : @shape.CollectionConstructionExtent = {
    record_headers: 0L,
    reference_slots: 0L,
    scalar_words: 0L,
  }
  let early : @shape.CollectionConstructionExtent = {
    record_headers: 2L,
    reference_slots: 1L,
    scalar_words: 2L,
  }
  if preparation_limits_invalid(limits) {
    return Some({ returned: early, temporary: zero, })
  }
  if g.stages < 0 ||
    g.object_views < 0 ||
    g.object_views > g.stages ||
    g.slot_maps < 0 ||
    g.slot_maps > g.object_views ||
    g.import_maps < g.slot_maps ||
    g.import_maps > g.object_views ||
    g.slots < 0L ||
    g.imports < 0L ||
    g.max_stage_fields < 0 ||
    g.inspection_work < 0L {
    return None
  }
  if g.stages > limits.max_work {
    guard @shape.map_construction_extent(1L, 0L) is Some(map) else {
      return None
    }
    guard @shape.add_collection_construction_extents(
        {
          record_headers: map.record_headers,
          reference_slots: map.reference_slots,
          scalar_words: map.scalar_words,
        },
        { record_headers: 2L, reference_slots: 0L, scalar_words: 3L, },
      )
      is Some(temporary) else {
      return None
    }
    // Original empty outer Map/Budget and Stop, before any Stage ObjectView.
    return Some({ returned: early, temporary, })
  }
  let s = g.slot_maps.to_int64()
  let n = g.slots
  let cursor = @decode.cursor_construction_extent()
  // Index1H3R, Usage1H2W, Ok1H1R1W; StageIndex1H1R1W and
  // Slot1H1R1W plus EACH retained original field_at Cursor. Fixed transient
  // field frames cannot cover these escaped wrappers. Original tree/usage/text
  // stay borrowed. Stop/flat-kind/Err3H1R3W alternatives co-counted.
  guard @shape.collection_construction_extent({
      records: 6L + s + n + n * cursor.record_headers,
      record_references: 5L + s + n + n * cursor.reference_slots,
      record_words: 6L + s + n + n * cursor.scalar_words,
      reference_arrays: 0L,
      reference_items: 0L,
      scalar_arrays: 0L,
      scalar_items: 0L,
      maps: 1L + s,
      map_entries: s + n,
    })
    is Some(returned) else {
    return None
  }
  guard @shape.collection_construction_extent({
      records: 0L,
      record_references: 0L,
      record_words: 0L,
      reference_arrays: 0L,
      reference_items: 0L,
      scalar_arrays: 0L,
      scalar_items: 0L,
      maps: g.import_maps.to_int64(),
      map_entries: g.imports,
    })
    is Some(imports) else {
    return None
  }
  let view = if g.object_views == 0 {
    zero
  } else {
    guard @decode.open_object_construction_extent(g.max_stage_fields)
      is Some(one) else {
      return None
    }
    let count = g.object_views.to_int64()
    guard @counts.checked_nonnegative_add_product(0L, one.record_headers, count)
      is Some(h) &&
      @counts.checked_nonnegative_add_product(0L, one.reference_slots, count)
      is Some(r) &&
      @counts.checked_nonnegative_add_product(0L, one.scalar_words, count)
      is Some(w) else {
      return None
    }
    { record_headers: h, reference_slots: r, scalar_words: w, }
  }
  let v = if g.object_views == 0 { 0L } else { 1L }
  let i = if g.slots == 0L { 0L } else { 1L }
  let m = if g.imports == 0L { 0L } else { 1L }
  let child = @decode.indexed_child_construction_extent()
  let field = @decode.indexed_field_construction_extent()
  // Budget; original Stage Some/root length Some/required child; two nested
  // field-at sites and local object length Some; original import tuple Some.
  let controls : @shape.CollectionConstructionExtent = {
    record_headers: 1L +
    2L * v +
    v * child.record_headers +
    2L * i * field.record_headers +
    i +
    m,
    reference_slots: v +
    v * child.reference_slots +
    2L * i * field.reference_slots +
    m,
    scalar_words: 2L +
    3L * v +
    v * child.scalar_words +
    2L * i * field.scalar_words +
    2L * i +
    m,
  }
  guard @shape.add_collection_construction_extents(imports, view)
    is Some(temporary) &&
    @shape.add_collection_construction_extents(temporary, controls)
    is Some(temporary) else {
    return None
  }
  let temporary = if g.object_views == 0 {
    temporary
  } else {
    guard @shape.add_collection_construction_extents(
        temporary, index_utf8_admission_units,
      )
      is Some(complete) else {
      return None
    }
    complete
  }
  Some({ returned, temporary, })
}

///|
// Transport the scalar owner's immutable units once. No duplicate scalar
// table, name-length multiplier or text rescan belongs to the Source index.
let index_utf8_admission_units : @shape.CollectionConstructionExtent = {
  let (record_headers, reference_slots, scalar_words) = @scalar.utf8_length_admission_construction_units()
  { record_headers, reference_slots, scalar_words, }
}
