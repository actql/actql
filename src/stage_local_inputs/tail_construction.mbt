///|
/// Completed constructor quantity on the SAME original Local read. This is
/// not a Resource Owner, semantic admission, replacement Source or policy.
pub(all) struct LocalCompletionConstructionInventory {
  peak : @environment.RegistryConstructionExtent
  retained : @environment.RegistryConstructionExtent
  inspection_work : Int64
} derive(Eq, Debug)

///|
priv struct LocalTailConstruction {
  inventory : LocalCompletionConstructionInventory?
}

///|
fn tail_units(
  value : @shape.CollectionConstructionExtent,
  text? : Int64 = 0L,
) -> @environment.RegistryConstructionExtent {
  {
    record_headers: value.record_headers,
    reference_slots: value.reference_slots,
    scalar_words: value.scalar_words,
    owned_utf16_units: text,
    owned_wire_bytes: 0L,
  }
}

///|
fn tail_add(
  a : @environment.RegistryConstructionExtent,
  b : @environment.RegistryConstructionExtent,
) -> @environment.RegistryConstructionExtent? {
  guard @shape.add_collection_construction_extents(
      {
        record_headers: a.record_headers,
        reference_slots: a.reference_slots,
        scalar_words: a.scalar_words,
      },
      {
        record_headers: b.record_headers,
        reference_slots: b.reference_slots,
        scalar_words: b.scalar_words,
      },
    )
    is Some(boxes) &&
    @counts.checked_nonnegative_add_product(
      a.owned_utf16_units,
      b.owned_utf16_units,
      1L,
    )
    is Some(text) &&
    @counts.checked_nonnegative_add_product(
      a.owned_wire_bytes,
      b.owned_wire_bytes,
      1L,
    )
    is Some(wire) else {
    return None
  }
  Some({
    record_headers: boxes.record_headers,
    reference_slots: boxes.reference_slots,
    scalar_words: boxes.scalar_words,
    owned_utf16_units: text,
    owned_wire_bytes: wire,
  })
}

///|
fn tail_peak(
  a : @environment.RegistryConstructionExtent,
  b : @environment.RegistryConstructionExtent,
) -> @environment.RegistryConstructionExtent {
  {
    record_headers: Int64::max(a.record_headers, b.record_headers),
    reference_slots: Int64::max(a.reference_slots, b.reference_slots),
    scalar_words: Int64::max(a.scalar_words, b.scalar_words),
    owned_utf16_units: Int64::max(a.owned_utf16_units, b.owned_utf16_units),
    owned_wire_bytes: Int64::max(a.owned_wire_bytes, b.owned_wire_bytes),
  }
}

///|
fn tail_inputs_cursor(stage : @syntax.Stage) -> @decode.Cursor {
  let root = @syntax.stage_body(stage)
  for i in 0..<@decode.object_length(root).unwrap() {
    let (key, value) = @decode.field_at(root, i).unwrap()
    if key == "inputs" {
      return value
    }
  }
  abort("original admitted Stage retains its inputs")
}

///|
// Actual declaration/source-view partition, in original row order. These
// metadata maps do not admit a declaration or replace its original full read.
fn quote_local_completion(
  read : LocalEnvironmentPreparation,
  original : LocalEnvironmentArguments,
) -> LocalCompletionConstructionInventory? {
  let zero = tail_units({
    record_headers: 0L,
    reference_slots: 0L,
    scalar_words: 0L,
  })
  let mut retained = zero
  let mut peak = zero
  let mut work = 0L
  for stage_index in 0..<read.count {
    let stage = @stages.stage_at(original.source, stage_index).unwrap()
    let inputs = tail_inputs_cursor(stage)
    let width = @decode.object_length(inputs).unwrap()
    let imports : Map[String, Bool] = Map([])
    for i in 0..<@syntax.import_count(stage) {
      let (name, _) = @syntax.import_at(stage, i).unwrap()
      imports[name] = true
      work += 1L
    }
    let declarations_by_name : Map[
      String,
      @local_input.ReadConstructionGeometry,
    ] = Map([])
    let mut declarations = 0
    let mut declaration_retained = zero
    let mut declaration_scratch = zero
    work += 3L
    for i in 0..<width {
      let (name, value) = @decode.field_at(inputs, i).unwrap()
      work += 2L
      if imports.contains(name) {
        continue
      }
      if original.sourceviews is Some(views) &&
        @sourceviews.input_for(views, stage_index, name) is Some(_) {
        continue
      }
      let geometry = @local_input.observe_read_construction_geometry(value)
      work += geometry.inspection_work
      declarations_by_name[name] = geometry
      declarations += 1
      guard @local_input.read_construction_inventory(geometry) is Some(body) else {
        return None
      }
      let returned = tail_units(body.retained)
      let scratch = tail_units(body.scratch, text=body.scratch_utf16_units)
      guard tail_add(declaration_retained, returned) is Some(held) else {
        return None
      }
      declaration_scratch = tail_peak(declaration_scratch, scratch)
      declaration_retained = held
    }
    let members = read.groups.unwrap().by_stage[stage_index]
    let m = members.length().to_int64()
    let d = declarations.to_int64()
    let mut agreements = zero
    let mut score_retained = zero
    let mut agreement_scratch = zero
    let mut score_scratch = zero
    let mut scored = 0L
    for selected in members {
      let snapshot = @snapshot.environment_snapshot(selected)
      let name = @source_ref.input_name(@snapshot.source_reference(snapshot))
      work += 1L
      guard declarations_by_name.get(name) is Some(declaration) else {
        continue
      }
      let (_, schema_nodes, _) = @environment.member_emission_geometry(
        @snapshot.environment_member(selected),
      )
      let schema_fields = @schema.field_count(@snapshot.schema(snapshot))
      guard @local_input.schema_agreement_construction_inventory(
          declaration, schema_nodes, schema_fields,
        )
        is Some(one) &&
        tail_add(agreements, tail_units(one.retained)) is Some(next) else {
        return None
      }
      agreements = next
      agreement_scratch = tail_peak(
        agreement_scratch,
        tail_units(one.scratch, text=one.scratch_utf16_units),
      )
      if @snapshot.score_count(snapshot) == 0 {
        continue
      }
      scored += 1L
      let source = @snapshot.score_source(snapshot).unwrap()
      let geometry = @decode.observe_subtree_geometry(source, [])
      let fields = @decode.object_length(source).unwrap()
      let mut text = 0L
      let mut largest = 0
      for i in 0..<fields {
        let (name, _) = @decode.field_at(source, i).unwrap()
        text += name.length().to_int64()
        largest = Int::max(largest, name.length())
        work += 2L
      }
      work += geometry.work + 1L
      guard @evidence.ranking_scores_construction_inventory(
          geometry, fields, text, largest,
        )
        is Some(scores) &&
        tail_add(
          score_retained,
          tail_units(scores.retained, text=scores.retained_utf16_units),
        )
        is Some(next) else {
        return None
      }
      score_retained = next
      score_scratch = tail_peak(
        score_scratch,
        tail_units(scores.scratch, text=scores.scratch_utf16_units),
      )
    }
    // Prepared/EnvironmentInputs/CheckedSnapshots/SchemaAssertions plus their
    // four Usage records8H18R13W. Per declaration: original input Cursor,
    // entry tuple, input-contract variant and registration tuple4H7R2W.
    // Each binding/agreement Some2H4R1W; scored snapshot Some and optional
    // existing KeySet/RelationEvidence add3H5R3W. Original child bodies share.
    let caller = @shape.collection_construction_extent({
      records: 8L + 4L * d + 2L * m + 3L * scored,
      record_references: 18L + 7L * d + 4L * m + 5L * scored,
      record_words: 13L + 2L * d + m + 3L * scored,
      reference_arrays: 6L + scored,
      reference_items: 4L * d + 2L * m + scored,
      scalar_arrays: 0L,
      scalar_items: 0L,
      maps: 0L,
      map_entries: 0L,
    }).unwrap()
    guard @refs.resolve_construction_inventory(members.length())
      is Some(resolution) &&
      tail_add(declaration_retained, tail_units(caller)) is Some(stage_retained) &&
      tail_add(stage_retained, agreements) is Some(stage_retained) &&
      tail_add(stage_retained, score_retained) is Some(stage_retained) &&
      tail_add(stage_retained, tail_units(resolution.retained))
      is Some(stage_retained) else {
      return None
    }
    // Original import/name/position maps are separate passes. Snapshot,
    // reference and supplied-schema work Arrays coexist only in those calls;
    // their tuple bodies borrow admitted Snapshot/schema/Reference instances.
    let frames = @shape.collection_construction_extent({
      records: m + 24L,
      record_references: 2L * m + 20L,
      record_words: 26L,
      reference_arrays: 3L,
      reference_items: 3L * m,
      scalar_arrays: 2L,
      scalar_items: 5L,
      maps: 4L,
      map_entries: 3L * d + @syntax.import_count(stage).to_int64(),
    }).unwrap()
    let root_view = @decode.open_object_construction_extent(
      @decode.object_length(@syntax.stage_body(stage)).unwrap(),
    ).unwrap()
    let frame = tail_units(
      @shape.add_collection_construction_extents(frames, root_view).unwrap(),
    )
    let mut child_peak = declaration_scratch
    for
      part in [agreement_scratch, score_scratch, tail_units(resolution.scratch)] {
      child_peak = tail_peak(child_peak, part)
    }
    let active = tail_add(
      retained,
      tail_add(stage_retained, tail_add(frame, child_peak).unwrap()).unwrap(),
    ).unwrap()
    peak = tail_peak(peak, active)
    retained = tail_add(retained, stage_retained).unwrap()
  }
  let t = read.count.to_int64()
  let m = read.members.to_int64()
  // Original positions and final mapped Stage vector, covered Bool vector,
  // final ProgramEnvironment/Usage and Source success forwarding. Prior
  // snapshot-funded empty read.stages already owns its headers; add only its
  // actual3T append slots here, never another growth header inventory.
  let assembly = @shape.collection_construction_extent({
    records: t + 8L,
    record_references: t + 10L,
    record_words: t + 12L,
    reference_arrays: 2L,
    reference_items: 2L * t,
    scalar_arrays: 2L,
    scalar_items: m + 2L,
    maps: 0L,
    map_entries: 0L,
  }).unwrap()
  let appended : @shape.CollectionConstructionExtent = {
    record_headers: 0L,
    reference_slots: 3L * t,
    scalar_words: 0L,
  }
  let assembly_peak = tail_add(
    retained,
    tail_units(
      @shape.add_collection_construction_extents(assembly, appended).unwrap(),
    ),
  ).unwrap()
  peak = tail_peak(peak, assembly_peak)
  // Only the new final Stage Array, ProgramEnvironment/Usage, Source success
  // carriers and retained last work Some survive assembly. Earlier empty
  // Stage-array backing stays in its already-owned prefix until final take.
  let final_output = @shape.collection_construction_extent({
    records: 6L,
    record_references: 8L,
    record_words: 7L,
    reference_arrays: 1L,
    reference_items: t,
    scalar_arrays: 0L,
    scalar_items: 0L,
    maps: 0L,
    map_entries: 0L,
  }).unwrap()
  let returned = tail_add(retained, tail_units(final_output)).unwrap()
  Some({ peak, retained: returned, inspection_work: work, })
}

///|
pub fn observe_local_environment_tail_construction(
  read : LocalEnvironmentPreparation,
) -> LocalCompletionConstructionInventory? {
  guard (read.state is ReadDeclaration(0) || read.state is AssembleStages) &&
    read.arguments is Some(original) else {
    return None
  }
  if read.tail_construction is Some(completed) {
    return completed.inventory
  }
  let inventory = quote_local_completion(read, original)
  // Failed quantity observation is cached as missing, never as zero work.
  read.tail_construction = Some({ inventory, })
  inventory
}

///|
pub fn local_environment_tail_construction(
  read : LocalEnvironmentPreparation,
) -> LocalCompletionConstructionInventory? {
  read.tail_construction.bind(completed => completed.inventory)
}

///|
pub fn local_environment_tail_inspection_bound(
  read : LocalEnvironmentPreparation,
) -> Int64? {
  guard (read.state is ReadDeclaration(0) || read.state is AssembleStages) &&
    read.arguments is Some(original) &&
    read.index_construction is Some(_) else {
    return None
  }
  let source = @decode.admission_usage(@stages.source_body(original.source))
  let (_, nodes, _) = @environment.usage(original.environment)
  // Whole original Source/Environment sizes bound the selected metadata visits
  // only, never memory demand, type work or a new user ceiling.
  Some(
    12L * source.nodes.to_int64() +
    12L * nodes.to_int64() +
    10L * read.count.to_int64() +
    1L,
  )
}

///|
// Source-site expansion of this fixed quotation tree, not an input-size or
// policy multiplier:49 collection expansions (including their9W argument),
//47 extent sums,4 direct Map expansions,5 key-path quantities,16 standalone
// checked sums,13 Registry sums and19 Registry conversions/maxima. Child
// constructors are sequential; co-counting each call-site family once bounds
// their active numeric overlap, never all iterations' discarded quantities.
// Dynamic geometry/import Maps are separate and use the completed Index.
let local_tail_quotation_controls : @shape.CollectionConstructionExtent = {
  let collection = @shape.collection_construction_quotation_extent()
  let field = @decode.indexed_field_construction_extent()
  let child = @decode.indexed_child_construction_extent()
  // Quantity-return records/Some40H50R59W;16 direct3W extent arguments;
  // three selected-width Some; six fixed reference Arrays with18 items;
  // six original field sites and one array-element site; nine scalar length
  // Some; eight lookup/result/original-access alternatives8H9R8W; two scalar
  // tuples2H6W and the score SubtreeGeometry1H9W. Original named Source,
  // Member and typed bodies remain borrowed. No NFC/semantic pass runs here.
  {
    record_headers: 49L * (collection.record_headers + 1L) +
    47L * 5L +
    4L * 8L +
    5L * 2L +
    16L +
    13L * 11L +
    19L +
    40L +
    16L +
    3L +
    18L +
    6L * field.record_headers +
    child.record_headers +
    9L +
    8L +
    2L +
    1L,
    reference_slots: 49L * collection.reference_slots +
    47L +
    4L +
    5L +
    13L * 2L +
    50L +
    132L +
    6L * field.reference_slots +
    child.reference_slots +
    9L,
    scalar_words: 49L * (collection.scalar_words + 9L) +
    47L * 10L +
    4L * 16L +
    5L * 5L +
    16L * 2L +
    13L * 26L +
    19L * 5L +
    59L +
    16L * 3L +
    3L * 2L +
    12L +
    6L * field.scalar_words +
    child.scalar_words +
    9L * 2L +
    8L +
    6L +
    9L,
  }
}

///|
pub fn local_environment_tail_inspection_extent(
  read : LocalEnvironmentPreparation,
) -> @shape.CollectionConstructionExtent? {
  guard (read.state is ReadDeclaration(0) || read.state is AssembleStages) &&
    read.index_construction is Some(original) else {
    return None
  }
  let geometry = original.geometry
  let maps = @shape.collection_construction_extent({
    records: 2L * geometry.slots + 6L,
    record_references: geometry.slots + 5L,
    record_words: 14L * geometry.slots + 13L,
    reference_arrays: 0L,
    reference_items: 0L,
    scalar_arrays: 0L,
    scalar_items: 0L,
    maps: 2L,
    map_entries: geometry.slots + geometry.imports,
  }).unwrap()
  @shape.add_collection_construction_extents(
    local_tail_quotation_controls, maps,
  )
}

///|
pub fn local_environment_tail_inspection_retained_extent() -> @shape.CollectionConstructionExtent {
  // Two5W extents, inventory/Some and original cache/Some. The work quantity
  // is retained only by a completed inventory, never manufactured on failure.
  { record_headers: 6L, reference_slots: 5L, scalar_words: 13L, }
}
