///|
/// Actual original registrations and policy ancestry, not semantic limits or
/// a recheck of Source, Catalog, declaration types or downstream column widths.
pub(all) struct SourceViewContextInputGeometry {
  stages : Int
  registrations : Int64
  policy_fields : Int
  policy_path_depth : Int
  inspection_work : Int64
} derive(Eq, Debug)

///|
pub fn source_registration_context_input_inspection_bound(
  read : SourceRegistrationRead,
) -> Int64? {
  guard read.state is RegistrationDone(Ok((views, _))) else { return None }
  let source = @source_inputs.source(
    @sourceviews.inputs(@sourceviews.pipeline_resolution(views)),
  )
  let (_, nodes, _) = @environment.usage(
    @sourceviews.pipeline_environment(views),
  )
  // Original index nodes bound only ancestor visits; never memory demand.
  Some(@stages.stage_count(source).to_int64() + nodes.to_int64() + 1L)
}

///|
pub fn observe_source_registration_context_input_geometry(
  read : SourceRegistrationRead,
) -> SourceViewContextInputGeometry? {
  guard read.state is RegistrationDone(Ok((views, _))) else { return None }
  let source = @source_inputs.source(
    @sourceviews.inputs(@sourceviews.pipeline_resolution(views)),
  )
  let count = @stages.stage_count(source)
  let mut registrations = 0L
  for i in 0..<count {
    registrations += @sourceviews.pipeline_input_count(views, i)
      .unwrap()
      .to_int64()
  }
  let policy = @environment.host_policy(
    @sourceviews.pipeline_environment(views),
  )
  let (depth, visited) = @decode.observe_cursor_path_depth(policy)
  Some({
    stages: count,
    registrations,
    policy_fields: @decode.object_length(policy).unwrap(),
    policy_path_depth: depth,
    inspection_work: count.to_int64() + visited + 1L,
  })
}

///|
pub fn sourceview_context_input_geometry_inspection_extent() -> @shape.CollectionConstructionExtent {
  // Selected stage/width/return Some, original depth/work pair, one active
  // range alternative and retained five-word geometry/Some. No input array.
  { record_headers: 8L, reference_slots: 2L, scalar_words: 14L, }
}

///|
pub fn sourceview_context_input_geometry_retained_extent() -> @shape.CollectionConstructionExtent {
  { record_headers: 2L, reference_slots: 1L, scalar_words: 6L, }
}

///|
pub(all) struct SourceViewContextInputConstructionInventory {
  peak : @shape.CollectionConstructionExtent
  retained : @shape.CollectionConstructionExtent
} derive(Eq, Debug)

///|
/// The original Context entrance only. Pipeline typing, Parameter binding,
/// capacities, Stage joining, identity and checking are separate constructors.
pub fn sourceview_context_input_construction_inventory(
  g : SourceViewContextInputGeometry,
) -> SourceViewContextInputConstructionInventory? {
  if g.stages < 0 ||
    g.registrations < 0L ||
    g.policy_fields < 0 ||
    g.policy_path_depth < 0 ||
    g.inspection_work < 0L {
    return None
  }
  guard @environment.calendar_selection_construction_extent(
      g.policy_fields,
      g.policy_path_depth,
    )
    is Some(calendar) else {
    return None
  }
  let t = g.stages.to_int64()
  // Program input1H8R3W, Context input1H2R, adjusted Limits1H8W;
  // optional Selection/Some2H5R2W and outer Ok1H1R1W. Registration tuples
  // and every admitted declaration body are the SAME borrowed originals.
  let retained = @shape.collection_construction_extent({
    records: 6L,
    record_references: 16L,
    record_words: 14L,
    reference_arrays: t + 1L,
    reference_items: t + g.registrations,
    scalar_arrays: 0L,
    scalar_items: 0L,
    maps: 0L,
    map_entries: 0L,
  }).unwrap()
  // Three original selected lookups3H2R3W, four typed return alternatives
  //4H4R4W, calendar/registration tuples2H2R2W, makei closure1H2R,
  // original foreign-stage carrier1H1W, original iteration2H2R2W.
  let caller : @shape.CollectionConstructionExtent = {
    record_headers: 13L,
    reference_slots: 12L,
    scalar_words: 12L,
  }
  @shape.add_collection_construction_extents(
    retained,
    @shape.add_collection_construction_extents(calendar, caller).unwrap(),
  ).map(peak => { peak, retained, })
}
