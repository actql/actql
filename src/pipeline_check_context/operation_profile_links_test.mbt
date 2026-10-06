///|
fn profiles_from_ranges(
  ranges : ProgramOperationRanges,
) -> ProgramOperationProfileLinks {
  let queries = check_program_operation_queries(ranges, 10000000, 100).unwrap()
  let cells = check_program_operation_cells(queries, 10000000, 100).unwrap()
  let lexical = check_program_operation_lexical(cells, None, 10000000, 100).unwrap()
  let calendar = check_program_operation_calendar(lexical, None, 10000000, 100).unwrap()
  link_program_operation_profiles(calendar, 10000000, 100).unwrap()
}

///|
test "VecA and TEA profile links retain checker claims without lexical artifacts" {
  let vectors = profiles_from_ranges(
    query_fixture("{\"$param\":\"n\"}", "[1,2]"),
  )
  assert_eq(operation_profile_links_count(vectors), 6)
  for i in 0..<6 {
    let entry = operation_profile_links_at(vectors, i).unwrap()
    assert_eq(entry.profile, @pipeline.VecA)
    assert_eq(operation_profile_adopted_law_count(entry), 1)
    assert_eq(
      operation_profile_adopted_law_at(entry, 0),
      Some(@pipeline.VecaNumeric),
    )
    assert_true(operation_profile_adopted_law_at(entry, 1) is None)
    assert_true(entry.lexical is None)
    assert_eq(entry.site.step, 2 + i % 2)
  }
  let requirements = operation_order_fixture(
    "[{\"values\":{\"schema\":{\"id\":{\"type\":\"number\",\"nullable\":false},\"time\":{\"type\":\"number\",\"nullable\":false}},\"rows\":[{\"id\":1,\"time\":0}]},\"as\":\"seed\"},{\"derive\":{\"p_copy\":\"$p\",\"n_copy\":\"$n\"}},{\"to_events\":{\"id\":\"id\",\"time\":\"time\"}}]",
    tea=true,
  )
  let orders = link_program_operation_orders(requirements, 10000000, 100).unwrap()
  let scalars = check_program_operation_scalars(orders, 10000000, 100).unwrap()
  let frames = check_program_operation_frames(scalars, 10000000, 100).unwrap()
  let fills = check_program_operation_fills(frames, 10000000, 100).unwrap()
  let ranges = check_program_operation_ranges(fills, 10000000, 100).unwrap()
  let events = profiles_from_ranges(ranges)
  assert_eq(operation_profile_links_count(events), 3)
  for i in 0..<3 {
    let entry = operation_profile_links_at(events, i).unwrap()
    assert_eq(entry.profile, @pipeline.TEA)
    assert_eq(operation_profile_adopted_law_count(entry), 0)
    assert_true(operation_profile_adopted_law_at(entry, 0) is None)
    assert_true(entry.lexical is None)
    assert_true(operation_profiles_declared(entry.checks).tea)
  }
}

///|
test "Graph profile links retain the construction owner across repeated producer visits" {
  let requirements = operation_order_fixture(
    property_execution_steps(),
    graph=true,
  )
  let orders = link_program_operation_orders(requirements, 10000000, 100).unwrap()
  let scalars = check_program_operation_scalars(orders, 10000000, 100).unwrap()
  let frames = check_program_operation_frames(scalars, 10000000, 100).unwrap()
  let fills = check_program_operation_fills(frames, 10000000, 100).unwrap()
  let result = profiles_from_ranges(
    check_program_operation_ranges(fills, 10000000, 100).unwrap(),
  )
  assert_eq(operation_profile_links_count(result), 3)
  for i in 0..<3 {
    let entry = operation_profile_links_at(result, i).unwrap()
    assert_eq(entry.profile, @pipeline.GraphProfile)
    assert_eq(operation_profile_adopted_law_count(entry), 1)
    assert_eq(
      operation_profile_adopted_law_at(entry, 0),
      Some(@pipeline.GraphLaw),
    )
    assert_true(operation_profile_adopted_law_at(entry, 1) is None)
    assert_true(entry.lexical is None)
    assert_true(operation_profiles_graph(entry.checks))
    assert_false(operation_profiles_declared(entry.checks).sga)
    assert_eq(entry.site.step, 2)
  }
}

///|
test "operation profile obligations consume the exact checked lexical sites" {
  for ranking in [false, true] {
    let cells = lexical_cells(lexical_host(), ranking)
    let artifact = lexical_artifact(cells)
    let lexical = check_program_operation_lexical(
      cells,
      Some(artifact),
      10000000,
      100,
    ).unwrap()
    let calendar = check_program_operation_calendar(
      lexical,
      None,
      10000000,
      100,
    ).unwrap()
    let result = link_program_operation_profiles(calendar, 10000000, 100).unwrap()
    assert_true(
      physical_equal(operation_profile_links_calendar(result), calendar),
    )
    let count = if ranking { 3 } else { 0 }
    assert_eq(operation_profile_links_count(result), count)
    for i in 0..<count {
      let entry = operation_profile_links_at(result, i).unwrap()
      assert_eq(entry.profile, @pipeline.TextRankProfile)
      assert_true(
        physical_equal(
          entry.lexical.unwrap(),
          operation_lexical_at(lexical, i).unwrap(),
        ),
      )
      assert_true(physical_equal(entry.lexical.unwrap().selected, artifact))
      assert_true(operation_profiles_declared(entry.checks).text_rank)
      assert_eq(
        @pipeline.operation_profile_requirement(entry.site.requirement),
        Some(entry.profile),
      )
      assert_eq(entry.site.step, 2)
      assert_eq(
        (entry.site.stage, entry.site.producer_visit),
        if i == 0 {
          (0, 0)
        } else {
          (1, i - 1)
        },
      )
    }
    for i in [-1, count, 2147483647] {
      assert_true(operation_profile_links_at(result, i) is None)
    }
    let work = operation_profile_links_work(result)
    assert_true(link_program_operation_profiles(calendar, work, count) is Ok(_))
    assert_true(
      link_program_operation_profiles(calendar, work - 1, count)
      is Err(BudgetExceeded),
    )
    assert_true(
      link_program_operation_profiles(calendar, -1, count) is Err(InvalidLimits),
    )
    assert_true(
      link_program_operation_profiles(calendar, work, -1) is Err(InvalidLimits),
    )
    if ranking {
      assert_true(
        link_program_operation_profiles(calendar, work, count - 1)
        is Err(BudgetExceeded),
      )
    }
  }
}
