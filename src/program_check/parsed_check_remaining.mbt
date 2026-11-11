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
  guard prepared.available else { return None }
  let contracts = match prepared.start {
    Requests(original, _) | ReusedRequests(original, _, _) => original
    _ => return None
  }
  let original = prepared.prelude.original
  let usage = @syntax.program_usage(original.program)
  let source = @decode.admission_preparation_data(
    @syntax.program_body(original.program),
  )
  // The raw supplied input is already retained separately. Its future Value
  // construction still needs its own variable-data backing in THIS quote.
  // Cached admission-owner dimensions require no binding or new tree walk.
  // A child Cursor conservatively retains its whole admitted owner's bounds.
  let (supplied_nodes, supplied_text) = match original.supplied {
    None => (0L, 0L)
    Some(cursor) =>
      (
        @decode.admission_usage(cursor).nodes.to_int64(),
        @decode.admission_preparation_data(cursor).total_utf16,
      )
  }
  // The independent input result remains live beside a possible tighter
  // ordinary fallback. Defaults borrow the Program body. Back both maximum
  // representations here, without raising either consumer's semantic caps.
  let (binding_nodes, binding_text) = if parsed_check_independent_supplied_original(
      prepared,
    )
    is Some(_) {
    (
      @counts.checked_nonnegative_add_product(
        usage.tree.nodes.to_int64(),
        supplied_nodes,
        1L,
      ),
      @counts.checked_nonnegative_add_product(
        source.total_utf16,
        supplied_text,
        1L,
      ),
    )
  } else {
    (Some(0L), Some(0L))
  }
  let program = @syntax.program_preparation_data(original.program)
  let environment = @environment.preparation_data_geometry(
    original.environment.wire,
    contracts,
  )
  let stages = usage.stages.to_int64()
  let operations = program.operations.to_int64()
  let results = program.results.to_int64()
  let lifetimes = operations + results + stages + 1L
  let width = Int::max(program.initial_fields, program.projected_fields).to_int64() +
    program.possible_growth.to_int64() +
    program.external_inputs.to_int64() * environment.max_fields
  // Borrow the original envelope's cached operand classification. Long literal
  // Values text remains fully backed below, but cannot become expression nodes.
  // Any other operand keeps the existing conservative parser envelope.
  let expression_nodes = if program.may_contain_expression_syntax {
    Int64::min(source.total_utf16, original.limits.artifacts.nodes.to_int64())
  } else {
    0L
  }
  guard binding_nodes is Some(binding_nodes) &&
    binding_text is Some(binding_text) &&
    @counts.checked_nonnegative_add_product(
      usage.tree.nodes.to_int64(),
      supplied_nodes,
      1L,
    )
    is Some(nodes) &&
    @counts.checked_nonnegative_add_product(nodes, binding_nodes, 1L)
    is Some(nodes) &&
    @counts.checked_nonnegative_add_product(nodes, environment.members, 1L)
    is Some(nodes) &&
    @counts.checked_nonnegative_add_product(nodes, expression_nodes, 1L)
    is Some(nodes) &&
    @counts.checked_nonnegative_add_product(0L, width, lifetimes)
    is Some(fields) &&
    @counts.checked_nonnegative_add_product(
      source.total_utf16,
      supplied_text,
      1L,
    )
    is Some(input_text) &&
    @counts.checked_nonnegative_add_product(input_text, binding_text, 1L)
    is Some(input_text) &&
    @counts.checked_nonnegative_add_product(
      input_text,
      fields,
      3L *
      (
        source.max_key_utf16.to_int64() +
        program.max_label_utf16.to_int64() +
        environment.max_name_utf16
      ) +
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
    inspection_work: 0L,
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
