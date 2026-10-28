///|
priv struct CoreStepConstruction {
  peak : @shape.CollectionConstructionExtent
  peak_utf16_units : Int64
  replaced : @shape.CollectionConstructionExtent
}

///|
let pipeline_core_zero_extent : @shape.CollectionConstructionExtent = {
  record_headers: 0L,
  reference_slots: 0L,
  scalar_words: 0L,
}

///|
/// Original read/body/state/Budget controls; no input/schema/typed operations,
/// limits policy or authority. Read1H1R, body1H31R15W, three state alternatives
/// 3H4R3W, Budget1H1R4W, elementsOk1H1R1W, begin2H2R2W, original evidence work getter1H2W,
/// take3H3R3W and original Issue/Stop alternatives2H4R2W.
fn pipeline_core_read_control_construction_extent() -> @shape.CollectionConstructionExtent {
  { record_headers: 15L, reference_slots: 47L, scalar_words: 32L, }
}

///|
fn pipeline_core_read_entry_construction(
  source : @decode.Cursor,
  input_count : Int,
) -> @shape.CollectionConstructionExtent? {
  if input_count < 0 {
    return None
  }
  let bodies = match @decode.array_length(source) {
    Some(count) =>
      @shape.collection_construction_extent({
        records: count.to_int64(),
        record_references: 2L * count.to_int64(),
        record_words: count.to_int64(),
        reference_arrays: 1L,
        reference_items: count.to_int64(),
        scalar_arrays: 0L,
        scalar_items: 0L,
        maps: 0L,
        map_entries: 0L,
      })
    // Known non-Array runs only the original issue path, not an empty body.
    None => Some({ record_headers: 0L, reference_slots: 0L, scalar_words: 0L, })
  }
  guard bodies is Some(bodies) &&
    @shape.collection_construction_extent({
      records: 0L,
      record_references: 0L,
      record_words: 0L,
      reference_arrays: 1L,
      reference_items: input_count.to_int64(),
      scalar_arrays: 0L,
      scalar_items: 0L,
      maps: 1L,
      map_entries: 0L,
    })
    is Some(inputs) &&
    @decode.issue_path_construction_extent(
      @decode.admission_usage(source).depth.to_int64(),
    )
    is Some(issue) else {
    return None
  }
  @shape.compose_collection_construction_extents([
    pipeline_core_read_control_construction_extent(),
    bodies,
    inputs,
    issue,
  ])
}

///|
/// Actual successful initializer output only, before Inputs admission. Original
/// source/schema/tuple bodies are borrowed. Only new Cursor wrappers, buffers,
/// empty names index and read/Budget controls survive this boundary.
fn pipeline_core_read_entry_holdings(
  original : PipelineCoreRead,
) -> @shape.CollectionConstructionExtent? {
  guard original.state is Reading(body) &&
    body.phase == Inputs &&
    @shape.reference_array_retained_extent(
      2L,
      body.inputs.capacity().to_int64() + body.bodies.capacity().to_int64(),
    )
    is Some(arrays) &&
    @shape.map_retained_extent(
      1L,
      body.names.capacity().to_int64(),
      body.names.length().to_int64(),
    )
    is Some(names) &&
    @shape.scale_collection_construction_extent(
      @decode.cursor_construction_extent(),
      body.bodies.length().to_int64(),
    )
    is Some(cursors) else {
    return None
  }
  @shape.compose_collection_construction_extents([
    arrays,
    names,
    cursors,
    // Original read/body/Reading/Budget4H34R20W.
    { record_headers: 4L, reference_slots: 34L, scalar_words: 20L, },
  ])
}
