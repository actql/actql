///|
fn quotation_supplied(text : String) -> @decode.Cursor {
  @decode.admit(
    @source.parse_json(text, {
      max_input_bytes: 100000,
      max_nodes: 10000,
      max_depth: 100,
    }).unwrap(),
    {
      max_nodes: 10000,
      max_depth: 100,
      max_string_bytes: 100000,
      max_total_string_bytes: 100000,
    },
  ).unwrap()
}

///|
fn quotation_registry(
  supplied : @decode.Cursor?,
  retained_source? : Bool = false,
  declaration_ceiling? : Int = 1,
) -> @program_check.ParsedCheckRegistry {
  let (_, program, environment, evidence, limits) = public_input_fixture(
    generated=true,
  )
  let source = if retained_source {
    Some(
      @stages.prepare(program, {
        max_parameters: declaration_ceiling,
        max_nodes: 1000,
        max_depth: 100,
        max_text_bytes: 10000,
      }).unwrap(),
    )
  } else {
    None
  }
  let input = @program_check.prepare_parsed_check_input(
    program,
    environment,
    supplied,
    evidence,
    limits,
    source_preparation=source,
  ).unwrap()
  let prelude = @program_check.observe_parsed_check_prelude(input).0.unwrap()
  let registry = @program_check.observe_parsed_check_registry(
    @program_check.prepare_parsed_catalog_input(prelude).unwrap(),
  ).0.unwrap()
  @program_check.observe_parsed_check_contents(
    @program_check.prepare_parsed_contents_input(registry).unwrap(),
  ).0.unwrap()
  @program_check.observe_parsed_check_references(
    @program_check.prepare_parsed_references_input(registry).unwrap(),
  ).0.unwrap()
  @program_check.observe_parsed_check_policies(
    @program_check.prepare_parsed_policies_input(registry).unwrap(),
  ).0.unwrap()
  @program_check.observe_parsed_check_values(
    @program_check.prepare_parsed_values_input(registry).unwrap(),
  ).0.unwrap()
  @program_check.observe_parsed_check_views(
    @program_check.prepare_parsed_views_input(registry).unwrap(),
  ).0.unwrap()
  @program_check.observe_parsed_check_carriers(
    @program_check.prepare_parsed_carriers_input(registry).unwrap(),
  ).0.unwrap()
  @program_check.observe_parsed_check_requests(
    @program_check.prepare_parsed_requests_input(registry).unwrap(),
  ).0.unwrap()
  registry
}

///|
fn quotation_estimate(
  supplied : @decode.Cursor?,
  retained_source? : Bool = false,
  declaration_ceiling? : Int = 1,
) -> @program_check.ParsedCheckDataEstimate raise {
  let registry = quotation_registry(
    supplied,
    retained_source~,
    declaration_ceiling~,
  )
  let before = @program_check.parsed_check_registry_remaining_work(registry)
  let first = @program_check.parsed_check_registry_data_estimate(registry).unwrap()
  let again = @program_check.parsed_check_registry_data_estimate(registry).unwrap()
  assert_eq(first.collections, again.collections)
  assert_eq(first.utf16_units, again.utf16_units)
  assert_eq(
    @program_check.parsed_check_registry_remaining_work(registry),
    before,
  )
  first
}

///|
test "remaining semantic quotation includes actual supplied nodes and text before binding" {
  let quotes : Array[@program_check.ParsedCheckDataEstimate] = []
  for
    supplied in [
      None,
      Some(quotation_supplied("{\"n\":7}")),
      Some(quotation_supplied("{\"n\":[" + "1,".repeat(31) + "1]}")),
      Some(quotation_supplied("{\"n\":\"" + "é😀".repeat(1000) + "\"}")),
    ] {
    quotes.push(quotation_estimate(supplied))
  }
  assert_true(quotes[1].collections.records > quotes[0].collections.records)
  assert_true(quotes[2].collections.records > quotes[1].collections.records)
  assert_true(
    quotes[2].collections.reference_items >
    quotes[1].collections.reference_items,
  )
  assert_eq(quotes[3].collections.records, quotes[1].collections.records)
  assert_true(quotes[3].utf16_units > quotes[1].utf16_units)
  // The identical Program/Catalog selects identical semantic work. These DATA
  // observations never bind the intentionally wrong array/string to number n.
  for quote in quotes {
    assert_eq(quote.semantic_work, quotes[0].semantic_work)
  }
}

///|
test "remaining semantic quotation conservatively retains an admitted parent for a supplied child" {
  let parent = quotation_supplied(
    "{\"payload\":{\"n\":7},\"unused\":\"" + "é😀".repeat(1000) + "\"}",
  )
  let child = @decode.required(@decode.open_object(parent).unwrap(), "payload").unwrap()
  let whole = quotation_estimate(Some(parent))
  let selected = quotation_estimate(Some(child))
  let small = quotation_estimate(Some(quotation_supplied("{\"n\":7}")))
  assert_eq(selected.collections, whole.collections)
  assert_eq(selected.utf16_units, whole.utf16_units)
  assert_eq(selected.semantic_work, small.semantic_work)
  assert_true(selected.collections.records > small.collections.records)
  assert_true(selected.utf16_units > small.utf16_units)
}

///|
test "remaining quotation backs an independent original binding beside the ordinary fallback" {
  let supplied = quotation_supplied("{\"n\":7}")
  let ordinary = quotation_estimate(Some(supplied))
  let retained = quotation_estimate(Some(supplied), retained_source=true)
  assert_true(retained.collections.records > ordinary.collections.records)
  assert_true(
    retained.collections.reference_items > ordinary.collections.reference_items,
  )
  assert_true(retained.utf16_units > ordinary.utf16_units)
  // This is additional representation backing, not an enlarged semantic cap.
  assert_eq(retained.semantic_work, ordinary.semantic_work)
  let absent = quotation_estimate(None)
  let absent_retained = quotation_estimate(None, retained_source=true)
  assert_eq(absent.collections, absent_retained.collections)
  assert_eq(absent.utf16_units, absent_retained.utf16_units)
  let incompatible = quotation_estimate(
    Some(supplied),
    retained_source=true,
    declaration_ceiling=1000000,
  )
  // The original declaration reuse rule refuses this older wider ceiling.
  // No independent input read is selected merely because a Source is held.
  assert_eq(incompatible.collections, ordinary.collections)
  assert_eq(incompatible.utf16_units, ordinary.utf16_units)
}
