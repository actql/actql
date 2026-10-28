///|
/// Variable-data estimate for one remaining semantic check. Fixed wrappers
/// belong to trusted Host overhead; these quantities carry no capacity grant.
pub(all) struct ParsedCheckDataEstimate {
  collections : @shape.CollectionConstructionInventory
  utf16_units : Int64
  inspection_work : Int64
  semantic_work : Int64
}

///|
/// The SAME admitted Program/Catalog dimensions. A Host retains this estimate
/// across a declined grow rather than repeating the observation or checker.
pub fn parsed_check_registry_data_estimate(
  prepared : ParsedCheckRegistry,
) -> ParsedCheckDataEstimate? {
  guard prepared.available &&
    (
      prepared.start is Requests(_, _) ||
      prepared.start is ReusedRequests(_, _, _)
    ) else {
    return None
  }
  let original = prepared.prelude.original
  let source = @decode.observe_subtree_construction_geometry(
    @syntax.program_body(original.program),
  )
  let environment = @environment.preparation_data_geometry(
    original.environment.wire,
  )
  let mut operations = 0L
  let mut results = 0L
  let mut inputs = 0L
  for stage in @syntax.stages(original.program) {
    inputs += @syntax.stage_input_declaration_count(stage).to_int64()
    operations += @decode.array_length(@syntax.stage_steps_source(stage))
      .unwrap()
      .to_int64()
    let body = @decode.open_object(@syntax.stage_body(stage)).unwrap()
    if @decode.lookup(body, "results") is Some(at) {
      results += @decode.object_length(at).unwrap_or(0).to_int64()
    }
  }
  let root = @decode.open_object(@syntax.program_body(original.program)).unwrap()
  if @decode.lookup(root, "results") is Some(at) {
    results += @decode.object_length(at).unwrap_or(0).to_int64()
  }
  let stages = @syntax.stage_count(original.program).to_int64()
  let expression_nodes = Int64::min(
    source.total_utf16,
    original.limits.artifacts.nodes.to_int64(),
  )
  let width = source.fields.to_int64() +
    source.texts.to_int64() +
    inputs * environment.max_fields
  let lifetimes = operations + results + stages + 1L
  guard @counts.checked_nonnegative_add_product(
      source.nodes.to_int64(),
      environment.members,
      1L,
    )
    is Some(nodes) &&
    @counts.checked_nonnegative_add_product(nodes, expression_nodes, 1L)
    is Some(nodes) &&
    @counts.checked_nonnegative_add_product(0L, width, lifetimes)
    is Some(fields) &&
    @counts.checked_nonnegative_add_product(source.total_utf16, 0L, 1L)
    is Some(text) &&
    @counts.checked_nonnegative_add_product(
      text,
      fields,
      source.max_text_utf16.to_int64() +
      source.max_key_utf16.to_int64() +
      environment.max_name_utf16 +
      6L,
    )
    is Some(text) &&
    @counts.checked_nonnegative_add_product(0L, nodes, 2L) is Some(records) &&
    @counts.checked_nonnegative_add_product(records, fields, 2L)
    is Some(records) &&
    @counts.checked_nonnegative_add_product(0L, nodes, 6L) is Some(references) &&
    @counts.checked_nonnegative_add_product(references, fields, 6L)
    is Some(references) &&
    @counts.checked_nonnegative_add_product(0L, nodes, 3L) is Some(words) &&
    @counts.checked_nonnegative_add_product(words, fields, 2L) is Some(words) &&
    @counts.checked_nonnegative_add_product(nodes, fields, 4L) is Some(items) else {
    return None
  }
  // Representative typed-node/schema/container storage, not a VM-layout proof.
  // The common collection owner supplies Array/Map growth and old/new overlap.
  Some({
    collections: {
      records,
      record_references: references,
      record_words: words,
      reference_arrays: operations + stages * 4L + 1L,
      reference_items: items,
      scalar_arrays: 0L,
      scalar_items: 0L,
      maps: operations + stages + 1L,
      map_entries: fields,
    },
    utf16_units: text,
    inspection_work: source.work + environment.inspection_work + stages + 1L,
    semantic_work: environment_start_budget(prepared.start).work.to_int64(),
  })
}

///|
/// Execute the original remaining checker ONCE. Success reports its original
/// budget delta. A rejected/incomplete constructor keeps an explicitly partial
/// known prefix; it never fabricates full failure Usage or zero total work.
pub fn observe_finish_parsed_check_registry(
  prepared : ParsedCheckRegistry,
) -> Result[(CheckOutcome, Int, Bool), ParsedCheckPreludeIssue] {
  let before = match parsed_check_registry_remaining_work(prepared) {
    Err(issue) => return Err(issue)
    Ok(value) => value
  }
  let outcome = match finish_parsed_check_registry(prepared) {
    Err(issue) => return Err(issue)
    Ok(value) => value
  }
  let remaining = prepared.prelude.budget.work
  let known = Int::max(0, before - remaining)
  let complete = outcome is Checked(_)
  Ok((outcome, known, complete))
}
