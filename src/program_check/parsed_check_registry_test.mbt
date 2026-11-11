///|
test "original registry prefix continues full retained and tighter Catalog routes once" {
  for route in [0, 1, 2] {
    let (_, program, environment, evidence, limits) = public_input_fixture(
      generated=true,
      repeated=true,
    )
    let catalog = if route == 0 {
      None
    } else {
      Some(
        @program_check.prepare_source_catalog(environment, {
          max_work: 10000000,
          max_bytes: 1000000,
          max_nodes: 100000,
          max_depth: if route == 2 {
            1000
          } else {
            limits.compilation.artifacts.depth
          },
        }).unwrap(),
      )
    }
    let original = @program_check.prepare_parsed_check_input(
      program,
      environment,
      None,
      evidence,
      limits,
      source_catalog=catalog,
    ).unwrap()
    let prelude = @program_check.observe_parsed_check_prelude(original).0.unwrap()
    let input = @program_check.prepare_parsed_catalog_input(prelude).unwrap()
    let extent = @program_check.parsed_catalog_construction_extent(input)
    if route == 1 {
      assert_eq(@program_check.parsed_catalog_inspection_work(input), 0)
      // The retained route adds its one actual collected-Inputs Ref to
      // the existing nine constructor/control records.
      assert_eq(extent.record_headers, 10L)
    } else {
      // This independent Values fixture has an ACTUAL empty registry; full
      // construction still creates its real entries Array and names Map.
      assert_eq(@program_check.parsed_catalog_inspection_work(input), 0)
      assert_true(extent.record_headers > 10L)
    }
    let initial_work = @program_check.parsed_catalog_semantic_work(input)
    let (result, spent) = @program_check.observe_parsed_check_registry(input)
    assert_true(spent > 0)
    assert_true(
      @program_check.finish_parsed_check_prelude(prelude)
      is Err(AlreadyConsumed),
    )
    let prepared = result.unwrap()
    let remaining = @program_check.parsed_check_registry_remaining_work(
      prepared,
    ).unwrap()
    assert_eq(
      remaining,
      @program_check.parsed_catalog_semantic_work(input) - spent,
    )
    evidence.clear()
    let checked = public_checked(
      @program_check.finish_parsed_check_registry(prepared).unwrap(),
    )
    assert_eq(@program_check.unit_count(checked), 2)
    assert_eq(@program_check.parsed_catalog_semantic_work(input), initial_work)
    assert_eq(
      @program_check.unit_result_import_at(checked, 1, 0).unwrap().producer_node_id,
      "producer",
    )
    assert_true(
      @program_check.finish_parsed_check_registry(prepared)
      is Err(AlreadyConsumed),
    )
    assert_true(
      @program_check.observe_parsed_check_registry(input).0
      is Err(Prelude(AlreadyConsumed)),
    )
  }
}

///|
test "registry prefix preserves required-reuse typed refusal instead of fresh reader" {
  let (_, program, environment, evidence, limits) = public_input_fixture(
    generated=true,
  )
  let catalog = @program_check.require_source_catalog_reuse(
    @program_check.prepare_source_catalog(environment, {
      max_work: 10000000,
      max_bytes: 1000000,
      max_nodes: 100000,
      max_depth: 1000,
    }).unwrap(),
  )
  let original = @program_check.prepare_parsed_check_input(
    program,
    environment,
    None,
    evidence,
    limits,
    source_catalog=Some(catalog),
  ).unwrap()
  let prelude = @program_check.observe_parsed_check_prelude(original).0.unwrap()
  let input = @program_check.prepare_parsed_catalog_input(prelude).unwrap()
  assert_eq(@program_check.parsed_catalog_inspection_work(input), 0)
  let (result, spent) = @program_check.observe_parsed_check_registry(input)
  assert_true(result is Err(Check(Environment(BudgetExceeded))))
  assert_eq(spent, 0)
}
