///|
test "same original continuation advances all Catalog readers then original full checker on full retained and tighter routes" {
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
    let registry_input = @program_check.prepare_parsed_catalog_input(prelude).unwrap()
    let owner = @program_check.observe_parsed_check_registry(registry_input).0.unwrap()
    let before = @program_check.parsed_check_registry_remaining_work(owner).unwrap()
    let input = @program_check.prepare_parsed_contents_input(owner).unwrap()
    assert_eq(@program_check.parsed_contents_semantic_work(input), before)
    assert_eq(
      @program_check.parsed_contents_inspection_work(input),
      if route == 1 {
        0L
      } else {
        4L
      },
    )
    let (result, spent) = @program_check.observe_parsed_check_contents(input)
    result.unwrap()
    assert_eq(
      @program_check.parsed_check_registry_remaining_work(owner),
      Ok(before - spent),
    )
    assert_eq(@program_check.parsed_contents_semantic_work(input), before)
    assert_true(
      @program_check.prepare_parsed_contents_input(owner)
      is Err(AlreadyConsumed),
    )
    assert_true(
      @program_check.observe_parsed_check_contents(input).0
      is Err(Prelude(AlreadyConsumed)),
    )
    let references = @program_check.prepare_parsed_references_input(owner).unwrap()
    let (result, used) = @program_check.observe_parsed_check_references(
      references,
    )
    result.unwrap()
    assert_true(if route == 1 { used == 0 } else { used > 0 })
    assert_true(
      @program_check.observe_parsed_check_references(references).0
      is Err(Prelude(AlreadyConsumed)),
    )
    let policies = @program_check.prepare_parsed_policies_input(owner).unwrap()
    let (result, used) = @program_check.observe_parsed_check_policies(policies)
    result.unwrap()
    assert_true(if route == 1 { used == 0 } else { used > 0 })
    assert_true(
      @program_check.observe_parsed_check_policies(policies).0
      is Err(Prelude(AlreadyConsumed)),
    )
    let value_input = @program_check.prepare_parsed_values_input(owner).unwrap()
    let (result, used) = @program_check.observe_parsed_check_values(value_input)
    result.unwrap()
    assert_true(if route == 1 { used == 0 } else { used > 0 })
    assert_true(
      @program_check.observe_parsed_check_values(value_input).0
      is Err(Prelude(AlreadyConsumed)),
    )
    let views = @program_check.prepare_parsed_views_input(owner).unwrap()
    let (result, used) = @program_check.observe_parsed_check_views(views)
    result.unwrap()
    assert_true(if route == 1 { used == 0 } else { used > 0 })
    assert_true(
      @program_check.observe_parsed_check_views(views).0
      is Err(Prelude(AlreadyConsumed)),
    )
    let carriers = @program_check.prepare_parsed_carriers_input(owner).unwrap()
    let (result, used) = @program_check.observe_parsed_check_carriers(carriers)
    result.unwrap()
    assert_true(if route == 1 { used == 0 } else { used > 0 })
    assert_true(
      @program_check.observe_parsed_check_carriers(carriers).0
      is Err(Prelude(AlreadyConsumed)),
    )
    let requests = @program_check.prepare_parsed_requests_input(owner).unwrap()
    let (result, used) = @program_check.observe_parsed_check_requests(requests)
    result.unwrap()
    assert_true(if route == 1 { used == 0 } else { used > 0 })
    assert_true(
      @program_check.observe_parsed_check_requests(requests).0
      is Err(Prelude(AlreadyConsumed)),
    )
    let checked = public_checked(
      @program_check.finish_parsed_check_registry(owner).unwrap(),
    )
    assert_eq(@program_check.unit_count(checked), 2)
    assert_eq(
      @program_check.unit_result_import_at(checked, 1, 0).unwrap().producer_node_id,
      "producer",
    )
    assert_true(
      @program_check.finish_parsed_check_registry(owner) is Err(AlreadyConsumed),
    )
  }
}
