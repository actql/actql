///|
fn lexical_cells(
  profile : String,
  ranking : Bool,
  tokenizer? : String = "unicode_words",
  same_input? : Bool = false,
) -> ProgramOperationCells {
  let steps = "[{\"values\":{\"schema\":{\"id\":{\"type\":\"string\",\"nullable\":false},\"text\":{\"type\":\"string\",\"nullable\":false}},\"rows\":[{\"id\":\"a\",\"text\":\"x\"}]},\"as\":\"seed\"},{\"derive\":{\"p_copy\":\"$p\",\"n_copy\":\"$n\"}}" +
    (if ranking {
      ",{\"text_rank\":{\"queries\":\"seed\",\"candidate_id\":\"id\",\"candidate_text\":\"text\",\"query_id\":\"id\",\"query_text\":\"text\",\"tokenizer\":\"unicode_words\",\"scoring\":{\"bm25\":{\"k1\":1.2,\"b\":0.75}},\"k\":1}}"
    } else {
      ""
    }) +
    "]"
  let requirements = operation_order_fixture(
    (if same_input {
      steps
      .replace(
        old="\"n_copy\":\"$n\"}}",
        new="\"n_copy\":\"$n\"},\"as\":\"prepared\"}",
      )
      .replace(old="\"queries\":\"seed\"", new="\"queries\":\"prepared\"")
    } else {
      steps
    }).replace(old="unicode_words", new=tokenizer),
    text_rank=true,
    host_profile=profile,
  )
  let orders = link_program_operation_orders(requirements, 10000000, 100).unwrap()
  let scalars = check_program_operation_scalars(orders, 10000000, 100).unwrap()
  let frames = check_program_operation_frames(scalars, 10000000, 100).unwrap()
  let fills = check_program_operation_fills(frames, 10000000, 100).unwrap()
  let ranges = check_program_operation_ranges(fills, 10000000, 100).unwrap()
  let queries = check_program_operation_queries(ranges, 10000000, 100).unwrap()
  check_program_operation_cells(queries, 10000000, 100).unwrap()
}

///|
fn lexical_host() -> String {
  // Insert into the fixture's canonical policy object without changing capacity.
  let base = bound_profile()
  base.replace(
    old="\"text_time_evaluation\":",
    new="\"text_rank\":{\"profile_bytes_cid\":\"" +
      text_profile_fixture_cid() +
      "\",\"version\":\"actql-text-rank-selection/0.1\"},\"text_time_evaluation\":",
  )
}

///|
fn operation_cells_environment(
  cells : ProgramOperationCells,
) -> @environment.WireEnvironment {
  let ranges = operation_queries_ranges(operation_cells_queries(cells))
  let scalars = operation_frames_scalars(
    operation_fills_frames(operation_ranges_fills(ranges)),
  )
  let requirements = operation_orders_requirements(
    operation_scalars_orders(scalars),
  )
  let identity = expression_closure_identity(
    operation_requirements_expressions(requirements),
  )
  let preparation = operation_profiles_preparation(
    program_sources_operations(program_identity_sources(identity)),
  )
  let selected = expression_validation_selected(
    expression_profiles_context(preparation_profiles(preparation)),
  )
  @environment.capacity_environment(selected_capacity(selected))
}

///|
fn lexical_artifact(
  cells : ProgramOperationCells,
) -> @environment.SelectedTextRankProfile {
  let env = operation_cells_environment(cells)
  let selection = @environment.read_text_rank_selection(env, 1000).unwrap()
  @environment.admit_text_rank_profile(
    selection,
    @utf8.encode(text_profile_fixture()),
    text_profile_blobs(),
    {
      max_profile_bytes: 10000,
      max_dependency_bytes: 1000,
      max_nodes: 1000,
      max_depth: 20,
    },
  ).unwrap()
}

///|
test "Program lexical profile resolution visits every producer and retains selected ownership" {
  let cells = lexical_cells(lexical_host(), true)
  let profile = lexical_artifact(cells)
  let result = check_program_operation_lexical(
    cells,
    Some(profile),
    10000000,
    3,
  ).unwrap()
  assert_eq(operation_lexical_count(result), 3)
  assert_true(physical_equal(operation_lexical_cells(result), cells))
  assert_true(
    physical_equal(operation_lexical_profile(result).unwrap(), profile),
  )
  for i in 0..<3 {
    let entry = operation_lexical_at(result, i).unwrap()
    assert_eq(entry.step, 2)
    assert_true(physical_equal(entry.selected, profile))
    assert_true(@vector.text_rank_profile(entry.operation) is None)
  }
  let work = operation_lexical_work(result)
  assert_true(
    check_program_operation_lexical(cells, Some(profile), work, 3) is Ok(_),
  )
  assert_true(
    check_program_operation_lexical(cells, Some(profile), work - 1, 3)
    is Err(BudgetExceeded),
  )
  assert_true(
    check_program_operation_lexical(cells, Some(profile), work, 2)
    is Err(BudgetExceeded),
  )
  assert_true(
    check_program_operation_lexical(cells, Some(profile), -1, 3)
    is Err(InvalidLimits),
  )
  assert_true(
    check_program_operation_lexical(cells, Some(profile), work, -1)
    is Err(InvalidLimits),
  )
  assert_true(operation_lexical_at(result, -1) is None)
  assert_true(operation_lexical_at(result, 3) is None)
  assert_true(
    check_program_operation_lexical(cells, None, work, 3)
    is Err(MissingArtifact(_)),
  )
  let foreign = lexical_artifact(lexical_cells(lexical_host(), true))
  assert_true(
    check_program_operation_lexical(cells, Some(foreign), work, 3)
    is Err(ForeignEnvironment),
  )
}

///|
test "absent lexical selection is allowed only without lexical consumers" {
  let cells = lexical_cells(bound_profile(), false)
  assert_eq(
    operation_lexical_count(
      check_program_operation_lexical(cells, None, 10000000, 0).unwrap(),
    ),
    0,
  )
  let ranking = lexical_cells(bound_profile(), true)
  assert_true(
    check_program_operation_lexical(ranking, None, 10000000, 3)
    is Err(MissingProfile(0, 0, 2)),
  )
  let unused = lexical_cells(lexical_host(), false)
  assert_true(
    check_program_operation_lexical(unused, None, 10000000, 0)
    is Err(MissingArtifact(_)),
  )
  assert_true(
    check_program_operation_lexical(
      unused,
      Some(lexical_artifact(unused)),
      10000000,
      0,
    )
    is Ok(_),
  )
  let malformed_host = lexical_host().replace(
    old="\"profile_bytes_cid\":\"" + text_profile_fixture_cid() + "\"",
    new="\"profile_bytes_cid\":null",
  )
  let malformed = lexical_cells(malformed_host, false)
  assert_true(
    check_program_operation_lexical(malformed, None, 10000000, 0)
    is Err(Selection(InvalidComponent)),
  )
}
